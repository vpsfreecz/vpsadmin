# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventRoute do
  before do
    reset_routing!(SpecSeed.user)
    allow(NotificationTemplate).to receive_messages(
      send_email!: build_mail_log_double,
      send_custom_email: build_mail_log_double
    )
  end

  def reset_routing!(user)
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    NotificationTarget.where(user:).delete_all
    EventRoute.where(user:).delete_all
    NotificationReceiver.where(user:).delete_all
    user.user_notification_delivery_methods.delete_all
  end

  def emit_incident!(user: SpecSeed.user, vps: nil, codename: 'Spec-Abuse')
    fixture = create_incident_report_fixture!(
      user:,
      vps:,
      subject: 'Spec incident',
      text: 'Spec incident body',
      codename:
    )
    incident = fixture.is_a?(Hash) ? fixture.fetch(:incident) : fixture

    VpsAdmin::API::Events.emit!(
      'vps.incident_report',
      user: incident.user,
      vps: incident.vps,
      source: incident,
      subject: incident.subject,
      summary: incident.text,
      parameters: {
        'codename' => incident.codename,
        'subject' => incident.subject,
        'text' => incident.text
      }
    )
  end

  def create_receiver!(user: SpecSeed.user, label: 'Spec receiver', mute: false, action: nil)
    receiver = NotificationReceiver.create!(user:, label:, mute:)

    if action
      if action[:action].to_s == 'email' && action[:target_kind].to_s == 'custom'
        action = action.merge(verified_at: Time.now)
      end

      receiver.notification_receiver_actions.create!(action)
    end

    receiver
  end

  def create_route!(user: SpecSeed.user, receiver: nil, position: 1, parent: nil, **attrs)
    described_class.create!(
      {
        user:,
        parent_event_route: parent,
        notification_receiver: receiver,
        event_type: 'vps.incident_report',
        position:
      }.merge(attrs)
    )
  end

  def event_notification_template!(name)
    NotificationTemplate.find_or_create_by!(name:) do |template|
      template.label = name.tr('_', ' ').capitalize
      template.template_id = name
      template.user_visibility = :default
    end
  end

  def reset_all_event_routing!
    EventRoutingContext.delete_all
    EventDelivery.delete_all
    Event.delete_all
    EventRouteMatcher.delete_all
    NotificationReceiverAction.delete_all
    NotificationTarget.delete_all
    EventRoute.delete_all
    NotificationReceiver.delete_all
  end

  def emit_oom_report!(stage)
    VpsAdmin::API::Events.emit!(
      'vps.oom_report',
      user: SpecSeed.user,
      subject: 'Spec OOM',
      parameters: {
        'stage' => stage,
        'cgroup' => '/user.slice/a.scope'
      }
    )
  end

  it 'creates and uses the default e-mail receiver when no routes exist' do
    event = emit_incident!
    delivery = event.event_deliveries.sole
    receivers = SpecSeed.user.notification_receivers.to_a

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route).to be_present
    expect(receivers.size).to eq(2)
    expect(receivers).to include(default_email_receiver_for(SpecSeed.user))
    expect(receivers).to include(default_mute_receiver_for(SpecSeed.user))
    expect(delivery.action).to eq('email')
    expect(delivery.target_kind).to eq('default_recipient')
    expect(delivery.target_value).to eq('default')
    expect(delivery.target_label).to eq('Default recipient')
    expect(delivery.template_name).to eq('vps_incident_report')
    expect(delivery.reload).to be_released_state
  end

  it 'does not route opt-in events through the generated default route' do
    event = VpsAdmin::API::Events.emit!(
      'transaction_chain.state_changed',
      user: SpecSeed.user,
      subject: 'Spec transaction state',
      parameters: {
        'state' => 'queued',
        'terminal' => false
      }
    )
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_suppressed_routing_state
    expect(event.matched_event_route).to be_nil
    expect(delivery).to be_skipped_state
    expect(delivery.error_summary).to eq('no route matched the event')
    expect(described_class.default_route_for(SpecSeed.user).hit_count).to eq(0)
  end

  it 'lets explicit wildcard routes match opt-in events' do
    receiver = create_receiver!(
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/transactions'
      }
    )
    route = create_route!(receiver:, event_type: nil)

    event = VpsAdmin::API::Events.emit!(
      'transaction_chain.state_changed',
      user: SpecSeed.user,
      subject: 'Spec transaction state',
      parameters: {
        'state' => 'queued',
        'terminal' => false
      }
    )

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route).to eq(route)
    expect(event.event_deliveries.sole.action).to eq('webhook')
  end

  it 'matches boolean false event parameters' do
    receiver = create_receiver!(
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/transactions'
      }
    )
    route = create_route!(
      receiver:,
      event_type: 'transaction_chain.state_changed'
    )
    route.event_route_matchers.create!(
      field: 'parameters.terminal',
      operator: '==',
      value: 'false'
    )

    event = VpsAdmin::API::Events.emit!(
      'transaction_chain.state_changed',
      user: SpecSeed.user,
      subject: 'Spec transaction state',
      parameters: {
        'state' => 'queued',
        'terminal' => false
      }
    )

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route).to eq(route)
  end

  it 'marks single-use routes as spent after their first match' do
    receiver = create_receiver!(
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/once'
      }
    )
    route = create_route!(
      receiver:,
      event_type: 'user.test_notification',
      single_use: true
    )

    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Spec one-shot'
    )

    expect(event.reload.matched_event_route).to eq(route)
    expect(route.reload).to be_single_use
    expect(route).not_to be_enabled
    expect(route.spent_at).to be_present
  end

  it 'can mute and restore default-routed events with generated receivers' do
    emit_incident!

    muted_receiver = mute_default_notifications_for!(SpecSeed.user)
    muted_event = emit_incident!
    muted_delivery = muted_event.event_deliveries.sole

    expect(muted_event.reload).to be_suppressed_routing_state
    expect(muted_delivery).to be_skipped_state
    expect(muted_delivery.notification_receiver).to eq(muted_receiver)

    route_default_notifications_to_email_for!(SpecSeed.user)
    routed_event = emit_incident!
    routed_delivery = routed_event.event_deliveries.sole

    expect(routed_event.reload).to be_routed_routing_state
    expect(routed_delivery.reload).to be_released_state
    expect(routed_delivery.action).to eq('email')
    expect(routed_delivery.target_value).to eq('default')
  end

  it 'does not overwrite user-managed default route receivers' do
    emit_incident!
    generated_mute_receiver = default_mute_receiver_for(SpecSeed.user)
    default_route = described_class.default_route_for(SpecSeed.user)
    custom_receiver = create_receiver!(
      label: 'Custom receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events'
      }
    )

    default_route.update!(notification_receiver: custom_receiver)
    NotificationReceiver.ensure_defaults_for!(SpecSeed.user)

    expect(custom_receiver.reload.label).to eq('Custom receiver')
    expect(custom_receiver).not_to be_mute
    expect(custom_receiver.notification_receiver_actions.count).to eq(1)
    expect(default_route.reload.notification_receiver).to eq(custom_receiver)
    expect(generated_mute_receiver.reload).to be_mute
  end

  it 'routes to a matching child receiver instead of the parent receiver' do
    parent_receiver = create_receiver!(
      label: 'Parent receiver',
      action: {
        action: :email,
        target_kind: :custom,
        target_value: 'parent@example.test'
      }
    )
    child_receiver = create_receiver!(
      label: 'Child receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events'
      }
    )
    parent = create_route!(receiver: parent_receiver)
    child = create_route!(receiver: child_receiver, parent:, position: 1)
    child.event_route_matchers.create!(
      field: 'parameters.codename',
      operator: '==',
      value: 'Spec-Abuse'
    )

    event = emit_incident!
    deliveries = event.event_deliveries.order(:id)

    expect(event.reload.matched_event_route).to eq(child)
    expect(deliveries.map(&:action)).to eq(['webhook'])
    expect(deliveries.first.target_value).to eq('https://example.test/events')
    expect(deliveries.first.template_name).to be_nil
    expect(deliveries.first).to be_released_state
  end

  it 'uses continue on matching sibling routes for additive delivery' do
    webhook_receiver = create_receiver!(
      label: 'Webhook receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events'
      }
    )
    email_receiver = create_receiver!(
      label: 'Audit receiver',
      action: {
        action: :email,
        target_kind: :custom,
        target_value: 'audit@example.test'
      }
    )
    create_route!(receiver: webhook_receiver, position: 1, continue: true)
    create_route!(receiver: email_receiver, position: 2)

    event = emit_incident!
    deliveries = event.event_deliveries.order(:id)

    expect(event.reload).to be_routed_routing_state
    expect(deliveries.map(&:action)).to eq(%w[webhook email])
    expect(deliveries.map(&:target_value)).to eq(
      ['https://example.test/events', 'audit@example.test']
    )
  end

  it 'skips unverified custom e-mail targets' do
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Pending e-mail receiver')
    receiver.notification_receiver_actions.create!(
      action: :email,
      target_kind: :custom,
      target_value: 'pending@example.test'
    )
    create_route!(receiver:)

    event = emit_incident!
    delivery = event.event_deliveries.sole

    expect(delivery).to be_skipped_state
    expect(delivery.error_summary).to eq('e-mail target is not verified')
  end

  it 'deduplicates equivalent actions from continuing routes' do
    first_receiver = create_receiver!(
      label: 'First webhook receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events'
      }
    )
    second_receiver = create_receiver!(
      label: 'Second webhook receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events'
      }
    )
    create_route!(receiver: first_receiver, position: 1, continue: true)
    create_route!(receiver: second_receiver, position: 2)

    event = emit_incident!
    deliveries = event.event_deliveries.to_a

    expect(deliveries.count).to eq(1)
    expect(deliveries.first.action).to eq('webhook')
    expect(deliveries.first.target_value).to eq('https://example.test/events')
  end

  it 'keeps webhook targets with distinct secrets' do
    first_receiver = create_receiver!(
      label: 'First webhook receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events',
        secret: 'first-secret'
      }
    )
    second_receiver = create_receiver!(
      label: 'Second webhook receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events',
        secret: 'second-secret'
      }
    )
    create_route!(receiver: first_receiver, position: 1, continue: true)
    create_route!(receiver: second_receiver, position: 2)

    event = emit_incident!
    deliveries = event.event_deliveries.order(:id).to_a

    expect(deliveries.count).to eq(2)
    expect(deliveries.map(&:action)).to eq(%w[webhook webhook])
    expect(deliveries.map(&:target_value)).to eq(
      ['https://example.test/events', 'https://example.test/events']
    )
    expect(deliveries.map(&:notification_target_id).uniq.size).to eq(2)
  end

  it 'deduplicates default e-mail actions with the same late-bound target' do
    first_receiver = create_receiver!(
      label: 'First e-mail receiver',
      action: {
        action: :email,
        target_kind: :default_recipient
      }
    )
    second_receiver = create_receiver!(
      label: 'Second e-mail receiver',
      action: {
        action: :email,
        target_kind: :default_recipient
      }
    )
    create_route!(receiver: first_receiver, position: 1, continue: true)
    create_route!(receiver: second_receiver, position: 2)

    event = emit_incident!
    deliveries = event.event_deliveries.to_a

    expect(deliveries.count).to eq(1)
    expect(deliveries.first.action).to eq('email')
    expect(deliveries.first.target_value).to eq('default')
  end

  it 'suppresses events through a mute receiver' do
    receiver = create_receiver!(label: 'Mute', mute: true)
    route = create_route!(receiver:)

    event = emit_incident!
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_suppressed_routing_state
    expect(event.matched_event_route).to eq(route)
    expect(delivery).to be_skipped_state
    expect(delivery.error_summary).to eq('receiver does not notify')
  end

  it 'creates a default mute receiver for every user' do
    reset_routing!(SpecSeed.user)
    muted_receiver = default_mute_receiver_for(SpecSeed.user)

    expect(muted_receiver).to be_mute
    expect(muted_receiver.label).to eq('Mute')
    expect(SpecSeed.user.notification_receivers.reload).to include(muted_receiver)
  end

  it 'materializes an admin-visible context only when a visible route matches' do
    reset_routing!(SpecSeed.admin)

    passive_event = emit_incident!
    passive_contexts = passive_event.event_routing_contexts.reload

    receiver = create_receiver!(
      user: SpecSeed.admin,
      label: 'Admin audit receiver',
      action: {
        action: :email,
        target_kind: :default_recipient
      }
    )
    route = create_route!(
      user: SpecSeed.admin,
      receiver:,
      event_type: 'vps.incident_report',
      subject_scope: :visible
    )
    route.event_route_matchers.create!(
      field: 'context.subject_relation',
      operator: '==',
      value: 'other_user'
    )

    routed_event = emit_incident!
    admin_delivery = routed_event.event_deliveries
                                 .joins(:event_routing_context)
                                 .find_by!(event_routing_contexts: { user_id: SpecSeed.admin.id })
    admin_context = admin_delivery.event_routing_context

    expect(passive_contexts.map(&:recipient_user)).to eq([SpecSeed.user])
    expect(routed_event.reload).to be_routed_routing_state
    expect(admin_context.recipient_user).to eq(SpecSeed.admin)
    expect(admin_context.subject_relation).to eq('other_user')
    expect(admin_context.source).to eq('visible_route')
    expect(admin_context.matched_event_route).to eq(route)
    expect(admin_delivery.target_value).to eq('default')
    expect(admin_delivery.recipient_user).to eq(SpecSeed.admin)
    expect(NotificationTemplate).to have_received(:send_email!).with(
      :vps_incident_report,
      hash_including(
        user: SpecSeed.admin,
        to: [SpecSeed.admin.email],
        include_default_recipients: false,
        include_template_recipients: false,
        vars: hash_including(user: SpecSeed.user)
      )
    )
  end

  it 'does not allow default routes to consume admin-visible events' do
    reset_routing!(SpecSeed.admin)
    receiver = create_receiver!(
      user: SpecSeed.admin,
      label: 'Admin default receiver',
      action: {
        action: :email,
        target_kind: :default_recipient
      }
    )
    create_route!(
      user: SpecSeed.admin,
      receiver:,
      default_route: true,
      position: EventRoute::DEFAULT_ROUTE_POSITION,
      event_type: nil,
      subject_scope: :self
    )

    event = emit_incident!

    expect(event.event_routing_contexts.where(user_id: SpecSeed.admin.id)).to be_empty
    expect(event.event_deliveries.map(&:recipient_user)).to eq([SpecSeed.user])
  end

  it 'routes role-addressed notifications with recipient role matchers' do
    receiver = create_receiver!(
      label: 'Account receiver',
      action: {
        action: :email,
        target_kind: :custom,
        target_value: 'account-role@example.test'
      }
    )
    route = create_route!(
      receiver:,
      event_type: 'user.suspended',
      template_name: 'user_suspend'
    )
    route.event_route_matchers.create!(
      field: 'parameters.recipient_roles',
      operator: 'contains',
      value: 'account'
    )

    event = VpsAdmin::API::Events.emit!(
      'user.suspended',
      user: SpecSeed.user,
      subject: 'Spec suspended user',
      parameters: {
        'state' => 'suspended',
        'recipient_roles' => %w[account]
      }
    )
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route).to eq(route)
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('account-role@example.test')
    expect(delivery.template_name).to eq('user_suspend')
  end

  it 'matches negated recipient role predicates' do
    receiver = create_receiver!(
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/non-account'
      }
    )
    route = create_route!(receiver:, event_type: 'user.suspended')
    route.event_route_matchers.create!(
      field: 'parameters.recipient_roles',
      operator: 'not_contains',
      value: 'account'
    )

    event = VpsAdmin::API::Events.emit!(
      'user.suspended',
      user: SpecSeed.user,
      subject: 'Spec suspended user',
      parameters: {
        'recipient_roles' => %w[admin]
      }
    )

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route).to eq(route)
  end

  it 'matches with sigil operators' do
    receiver = create_receiver!(
      action: {
        action: :email,
        target_kind: :custom,
        target_value: 'audit@example.test'
      }
    )
    route = create_route!(receiver:)
    route.event_route_matchers.create!(
      field: 'parameters.codename',
      operator: '=~',
      value: '^Spec-'
    )

    event = emit_incident!

    expect(event.reload).to be_routed_routing_state
    expect(event.event_deliveries.sole.target_value).to eq('audit@example.test')
  end

  it 'matches glob sigil operators' do
    receiver = create_receiver!(
      action: {
        action: :email,
        target_kind: :custom,
        target_value: 'audit@example.test'
      }
    )
    route = create_route!(receiver:, event_type: 'vps.oom_report')
    route.event_route_matchers.create!(
      field: 'parameters.cgroup',
      operator: '=*',
      value: '/user.slice/*.scope'
    )

    event = VpsAdmin::API::Events.emit!(
      'vps.oom_report',
      user: SpecSeed.user,
      subject: 'Spec OOM',
      parameters: {
        'cgroup' => '/user.slice/a.scope'
      }
    )

    expect(event.reload).to be_routed_routing_state
    expect(event.event_deliveries.sole.target_value).to eq('audit@example.test')
  end

  it 'rejects events with a VPS that belongs to another user' do
    vps = build_standalone_vps_fixture(user: SpecSeed.other_user).fetch(:vps)

    expect do
      emit_incident!(user: SpecSeed.user, vps:)
    end.to raise_error(ArgumentError, /VPS owner/)

    expect(Event.where(vps:)).to be_empty
  end
end
