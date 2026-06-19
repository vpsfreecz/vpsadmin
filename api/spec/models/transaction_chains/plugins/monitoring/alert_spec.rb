# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'monitoring alert chain', requires_plugins: :monitoring do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
  end

  def build_event(user: SpecSeed.user, object: SpecSeed.user)
    MonitoredEvent.create!(
      monitor_name: 'alert_chain',
      class_name: object.class.name,
      row_id: object.id,
      state: :confirmed,
      user:,
      access_level: 0
    ).tap do |event|
      event.object = object
    end
  end

  def reset_routing!(user)
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    EventRoute.where(user:).delete_all
    NotificationReceiver.where(user:).delete_all
    user.update!(mailer_enabled: true)
  end

  def create_webhook_route!(user)
    receiver = NotificationReceiver.create!(user:, label: 'Spec receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :webhook,
      label: 'Spec webhook',
      target_kind: :custom,
      target_value: 'https://example.test/events'
    )
    route = EventRoute.create!(
      user:,
      notification_receiver: receiver,
      event_type: 'monitoring.alert',
      position: 1
    )

    [action, route]
  end

  it 'registers the monitoring alert event type from the plugin' do
    type = VpsAdmin::API::Events.type_for('monitoring.alert')

    expect(type).to have_attributes(
      label: 'Monitoring alert',
      category: 'monitoring',
      default_routed: true
    )
  end

  it 'concerns the monitored object, invokes the action, and increments alert count when non-empty' do
    event = build_event
    allow(event).to receive(:call_action) do |chain, _ev|
      chain.append_t(Transactions::Utils::NoOp, args: SpecSeed.node.id)
    end

    chain, = chain_class.fire2(args: [event])

    expect(event).to have_received(:call_action).with(kind_of(TransactionChain), event)
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['User', SpecSeed.user.id]
    )
    expect(event.reload.alert_count).to eq(1)
  end

  it 'does not increment alert count when the action leaves the chain empty' do
    event = build_event
    allow(event).to receive(:call_action)

    chain, = chain_class.fire2(args: [event])

    expect(chain).to be_nil
    expect(event.reload.alert_count).to eq(0)
  end

  it 'routes monitoring alerts through the event system' do
    event = build_event
    action, route = create_webhook_route!(event.user)
    allow(event).to receive(:call_action) do |chain, ev|
      chain.route_monitoring_alert!(
        ev,
        role: 'user',
        template_name: :alert_role_event_state,
        template_params: {
          role: :user,
          event: ev.monitor_name,
          state: ev.state
        }
      )
    end

    chain = nil
    expect do
      chain, = chain_class.fire2(args: [event])
    end.to change { Event.where(event_type: 'monitoring.alert').count }.by(1)

    routed_event = Event.where(event_type: 'monitoring.alert').order(:id).last
    delivery = routed_event.event_deliveries.sole

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    expect(routed_event).to have_attributes(
      user: event.user,
      event_type: 'monitoring.alert',
      category: 'monitoring',
      severity: 'warning',
      source_class: 'MonitoredEvent',
      source_id: event.id
    )
    expect(routed_event.parameters).to include(
      'role' => 'user',
      'monitor_name' => 'alert_chain',
      'monitored_event_id' => event.id,
      'state' => 'confirmed',
      'object_class' => event.class_name,
      'object_id' => event.row_id
    )
    expect(routed_event.matched_event_route).to eq(route)
    expect(delivery).to have_attributes(
      action: 'webhook',
      notification_receiver_action: action,
      state: 'prepared'
    )
    expect(delivery.payload).to be_present
    expect(event.reload.alert_count).to eq(1)
  end

  it 'uses the generated default route for monitoring alerts' do
    event = build_event
    reset_routing!(event.user)
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
    allow(event).to receive(:call_action) do |chain, ev|
      chain.route_monitoring_alert!(
        ev,
        template_name: :alert_role_event_state,
        email_options: chain.monitoring_mail_thread_options(ev)
      )
    end

    chain, = chain_class.fire2(args: [event])
    routed_event = Event.where(event_type: 'monitoring.alert').order(:id).last
    delivery = routed_event.event_deliveries.sole

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    expect(routed_event.event_type).to eq('monitoring.alert')
    expect(routed_event.matched_event_route).to eq(EventRoute.default_route_for(event.user))
    expect(delivery).to have_attributes(
      action: 'email',
      target_kind: 'default_recipient',
      target_value: 'default',
      template_name: 'alert_role_event_state',
      state: 'prepared'
    )
    expect(MailTemplate).to have_received(:send_mail!).with(
      :alert_role_event_state,
      hash_including(
        user: event.user,
        include_template_recipients: false,
        message_id: "<vpsadmin-monitoring-alert-#{event.id}-1-confirmed@vpsadmin.vpsfree.cz>"
      )
    )
  end

  it 'uses the configurable monitoring alert message id format' do
    event = build_event
    cfg = SysConfig.find_by!(category: 'plugin_monitoring', name: 'alert_message_id')
    cfg.update!(value: '<monitor-%{event_id}-%{alert_id}-%{state}@alerts.example>')

    expect(chain_class.new.monitoring_mail_thread_options(event)).to include(
      message_id: "<monitor-#{event.id}-1-confirmed@alerts.example>"
    )
  end

  it 'routes admin monitoring alerts to active admins including level 90' do
    level90_admin = SpecSeed.create_or_update_user!(
      login: 'level90admin',
      level: 90,
      email: 'level90admin@test.invalid'
    )
    suspended_admin = SpecSeed.create_or_update_user!(
      login: 'suspendedadmin',
      level: 99,
      email: 'suspendedadmin@test.invalid'
    )
    suspended_admin.update!(object_state: 'suspended')

    expect(chain_class.new.monitoring_admin_recipients).to contain_exactly(
      SpecSeed.admin,
      level90_admin
    )
  end

  it 'keeps non-notification transactions in the alert chain' do
    event = build_event
    create_webhook_route!(event.user)
    allow(event).to receive(:call_action) do |chain, ev|
      chain.route_monitoring_alert!(ev)
      chain.append_t(Transactions::Utils::NoOp, args: SpecSeed.node.id)
    end

    chain, = chain_class.fire2(args: [event])

    expect(tx_classes(chain)).to include(
      Transactions::EventDelivery::Release,
      Transactions::Utils::NoOp
    )
    expect(event.reload.alert_count).to eq(1)
  end
end
