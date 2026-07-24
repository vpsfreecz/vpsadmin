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
    EventRouteMatch.delete_all
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    EventRouteTimeInterval
      .joins(:event_route)
      .where(event_routes: { user_id: user.id })
      .delete_all
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    NotificationTarget.where(user:).delete_all
    EventRoute.where(user:).delete_all
    EventTimeInterval.where(user:).delete_all
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
      payload: {
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
    EventRouteMatch.delete_all
    EventRoutingContext.delete_all
    EventDelivery.delete_all
    Event.delete_all
    EventRouteMatcher.delete_all
    EventRouteTimeInterval.delete_all
    NotificationReceiverAction.delete_all
    NotificationTarget.delete_all
    EventRoute.delete_all
    EventTimeInterval.delete_all
    NotificationReceiver.delete_all
  end

  def build_matcher(event_type:, field:, operator:, value:)
    route = create_route!(
      event_type:,
      position: EventRoute.where(user: SpecSeed.user).count + 1
    )
    route.event_route_matchers.create!(field:, operator:, value:)
  end

  def build_event(event_type:, payload:)
    Event.new(
      user: SpecSeed.user,
      event_type:,
      subject: 'Spec event',
      payload:
    )
  end

  def create_time_interval!(specs:, user: SpecSeed.user, name: 'Spec interval')
    EventTimeInterval.create!(user:, name:, time_zone: 'UTC', specs:)
  end

  def route_event_at!(time, event_type: 'vps.incident_report', payload: {})
    event = build_event(event_type:, payload:)
    event.created_at = time
    VpsAdmin::API::Events::Router.new(event).route!
    event
  end

  def matched_routes(event)
    event.event_route_matches.reload.map(&:event_route)
  end

  it 'creates and uses the default e-mail receiver when no routes exist' do
    event = emit_incident!
    delivery = event.event_deliveries.sole
    receivers = SpecSeed.user.notification_receivers.to_a

    expect(event.reload).to be_routed_routing_state
    expect(matched_routes(event)).to eq([described_class.default_admin_route_for(SpecSeed.user)])
    expect(receivers.size).to eq(2)
    expect(default_email_receiver_for(SpecSeed.user).label).to eq('Default')
    expect(default_email_receiver_for(SpecSeed.user).notification_receiver_actions.sole.label).to eq('Default')
    expect(receivers).to include(default_email_receiver_for(SpecSeed.user))
    expect(receivers).to include(default_mute_receiver_for(SpecSeed.user))
    expect(delivery.action).to eq('email')
    expect(delivery.target_kind).to eq('default_recipient')
    expect(delivery.target_value).to eq('default')
    expect(delivery.target_label).to eq('Default recipient')
    expect(delivery.template_name).to eq('vps_incident_report')
    expect(delivery.reload).to be_released_state
  end

  it 'normalizes legacy default e-mail receiver and target labels' do
    legacy_receiver = NotificationReceiver.create!(
      user: SpecSeed.user,
      label: 'Default e-mail',
      description: NotificationReceiver::LEGACY_DEFAULT_EMAIL_DESCRIPTION,
      mute: false
    )
    legacy_target = SpecSeed.user.notification_targets.new(
      action: 'email',
      label: 'Default e-mail',
      target_kind: :default_recipient,
      identity_key: 'default'
    )
    legacy_target.skip_delivery_method_enabled_validation = true
    legacy_target.save!

    receiver = NotificationReceiver.ensure_default_email_receiver_for!(SpecSeed.user)

    expect(receiver).to eq(legacy_receiver)
    expect(receiver.reload.label).to eq('Default')
    expect(receiver.description).to eq(NotificationReceiver::DEFAULT_EMAIL_DESCRIPTION)
    expect(legacy_target.reload.label).to eq('Default')
    expect(SpecSeed.user.notification_receivers.where(mute: false).count).to eq(1)
    expect(SpecSeed.user.notification_targets.where(action: 'email', identity_key: 'default').count).to eq(1)
  end

  it 'does not route opt-in events through the generated default route' do
    event = nil

    expect do
      event = VpsAdmin::API::Events.emit!(
        'transaction_chain.state_changed',
        user: SpecSeed.user,
        subject: 'Spec transaction state',
        payload: {
          'state' => 'queued',
          'terminal' => false
        }
      )
    end.not_to change(Event, :count)

    expect(event).to be_nil
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
      payload: {
        'state' => 'queued',
        'terminal' => false
      }
    )

    expect(event.reload).to be_routed_routing_state
    expect(matched_routes(event)).to eq([route])
    expect(event.event_deliveries.sole.action).to eq('webhook')
  end

  it 'lets custom routes match default-routed event types through a matcher' do
    receiver = create_receiver!(
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/default-routed'
      }
    )
    route = create_route!(receiver:, event_type: nil)
    route.event_route_matchers.create!(
      field: EventRoute::DEFAULT_ROUTE_MATCHER_FIELD,
      operator: EventRoute::DEFAULT_ROUTE_MATCHER_OPERATOR,
      value: EventRoute::DEFAULT_ROUTE_MATCHER_VALUE
    )

    routed_event = emit_incident!
    opt_in_event = VpsAdmin::API::Events.emit!(
      'transaction_chain.state_changed',
      user: SpecSeed.user,
      subject: 'Spec transaction state',
      payload: {
        'state' => 'queued',
        'terminal' => false
      }
    )

    expect(matched_routes(routed_event.reload)).to eq([route])
    expect(routed_event.event_deliveries.sole.target_value).to eq('https://example.test/default-routed')
    expect(opt_in_event).to be_nil
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
      field: 'terminal',
      operator: '==',
      value: 'false'
    )

    event = VpsAdmin::API::Events.emit!(
      'transaction_chain.state_changed',
      user: SpecSeed.user,
      subject: 'Spec transaction state',
      payload: {
        'state' => 'queued',
        'terminal' => false
      }
    )

    expect(event.reload).to be_routed_routing_state
    expect(matched_routes(event)).to eq([route])
  end

  it 'does not match payload keys undeclared by the event type' do
    receiver = create_receiver!(
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/undeclared-field'
      }
    )
    route = create_route!(receiver:, event_type: nil)
    route.event_route_matchers.create!(
      field: 'changed_at',
      operator: '==',
      value: '2026-07-01T12:00:00Z'
    )

    event = VpsAdmin::API::Events.emit!(
      'vps.incident_report',
      user: SpecSeed.user,
      subject: 'Spec incident',
      payload: {
        'codename' => 'Spec-Abuse',
        'subject' => 'Spec incident',
        'text' => 'Spec incident body',
        'changed_at' => '2026-07-01T12:00:00Z'
      }
    )

    expect(matched_routes(event.reload)).not_to include(route)
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

    expect(matched_routes(event.reload)).to eq([route])
    expect(route.reload).to be_single_use
    expect(route).not_to be_enabled
    expect(route.spent_at).to be_present
  end

  it 'can mute and restore default-routed events with generated receivers' do
    emit_incident!

    muted_receiver = mute_default_notifications_for!(SpecSeed.user, role: 'admin')
    muted_event = nil

    expect do
      muted_event = emit_incident!
    end.to change(Event, :count).by(1)

    muted_route = described_class.default_admin_route_for(SpecSeed.user)
    muted_delivery = muted_event.event_deliveries.sole
    expect(muted_event.reload).to be_suppressed_routing_state
    expect(matched_routes(muted_event)).to eq([muted_route])
    expect(muted_delivery).to be_skipped_state
    expect(muted_delivery.notification_receiver).to eq(muted_receiver)
    expect(muted_receiver.reload).to be_mute

    route_default_notifications_to_email_for!(SpecSeed.user, role: 'admin')
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
    default_route = described_class.default_admin_route_for(SpecSeed.user)
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

  it 'does not treat custom receiverless default-routed groups as the generated default route' do
    parent = create_route!(
      label: 'Default-routed group',
      receiver: nil,
      event_type: nil
    )
    parent.event_route_matchers.create!(
      field: 'default_routed',
      operator: '==',
      value: 'true'
    )
    child_receiver = create_receiver!(
      label: 'Child receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/child'
      }
    )
    child = create_route!(
      receiver: child_receiver,
      parent:,
      event_type: nil
    )

    NotificationReceiver.ensure_defaults_for!(SpecSeed.user)

    generated_default_route = described_class.default_route_for(SpecSeed.user)
    expect(generated_default_route).to be_present
    expect(generated_default_route).not_to eq(parent)
    expect(parent.reload.notification_receiver).to be_nil

    event = emit_incident!

    expect(matched_routes(event.reload)).to eq([parent, child])
    expect(event.event_deliveries.where(notification_receiver: child_receiver).count).to eq(1)
  end

  it 'routes to both parent and matching child receivers' do
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
      field: 'codename',
      operator: '==',
      value: 'Spec-Abuse'
    )

    event = emit_incident!
    deliveries = event.event_deliveries.order(:id)

    expect(matched_routes(event.reload)).to eq([parent, child])
    expect(deliveries.map(&:action)).to eq(%w[email webhook])
    expect(deliveries.map(&:target_value)).to eq(
      ['parent@example.test', 'https://example.test/events']
    )
    expect(deliveries.map(&:template_name)).to eq(['vps_incident_report', nil])
    expect(deliveries).to all(be_released_state)
  end

  it 'gates only the scheduled route receiver and still traverses matching children' do
    parent_receiver = create_receiver!(
      label: 'Scheduled parent',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/parent'
      }
    )
    child_receiver = create_receiver!(
      label: 'Unscheduled child',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/child'
      }
    )
    parent = create_route!(receiver: parent_receiver)
    child = create_route!(receiver: child_receiver, parent:)
    inactive = create_time_interval!(specs: [{ years: [{ start: 2025 }] }])
    parent.event_route_time_intervals.create!(event_time_interval: inactive, mode: :active)

    event = route_event_at!(Time.utc(2026, 7, 22, 12, 0))
    deliveries = event.event_deliveries.order(:id).to_a
    matches = event.event_route_matches.order(:match_order).to_a

    expect(event.reload).to be_routed_routing_state
    expect(matches.map(&:event_route)).to eq([parent, child])
    expect(matches.map(&:time_interval_state)).to eq(%w[inactive active])
    expect(matches.first.time_interval_snapshot).to include(
      'state' => 'inactive',
      'evaluated_at' => '2026-07-22T12:00:00Z'
    )
    expect(deliveries.map(&:state)).to eq(%w[skipped prepared])
    expect(deliveries.map(&:error_summary)).to eq(
      ['route is outside its active time intervals', nil]
    )
  end

  it 'lets mute intervals override matching active intervals' do
    receiver = create_receiver!(
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/muted'
      }
    )
    route = create_route!(receiver:)
    active = create_time_interval!(
      name: 'Always active in 2026',
      specs: [{ years: [{ start: 2026 }] }]
    )
    mute = create_time_interval!(
      name: 'Muted in July',
      specs: [{ months: [{ start: 7 }] }]
    )
    route.event_route_time_intervals.create!(event_time_interval: active, mode: :active)
    route.event_route_time_intervals.create!(event_time_interval: mute, mode: :mute)

    event = route_event_at!(Time.utc(2026, 7, 22, 12, 0))
    match = event.event_route_matches.sole
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_suppressed_routing_state
    expect(match.time_interval_state).to eq('muted')
    expect(match.time_interval_snapshot.fetch('assignments').map { |row| row.fetch('matched') }).to eq([true, true])
    expect(delivery).to be_skipped_state
    expect(delivery.error_summary).to eq('route is muted by a time interval')
  end

  it 'preserves continue and stop behavior when a route schedule suppresses delivery' do
    first_receiver = create_receiver!(
      label: 'Inactive first receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/first'
      }
    )
    second_receiver = create_receiver!(
      label: 'Second receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/second'
      }
    )
    first = create_route!(receiver: first_receiver, position: 1, continue: true)
    second = create_route!(receiver: second_receiver, position: 2)
    inactive = create_time_interval!(specs: [{ years: [{ start: 2025 }] }])
    first.event_route_time_intervals.create!(event_time_interval: inactive, mode: :active)

    continued = route_event_at!(Time.utc(2026, 7, 22, 12, 0))

    expect(matched_routes(continued)).to eq([first, second])
    expect(continued.event_deliveries.pluck(:state)).to contain_exactly('skipped', 'prepared')

    first.update!(continue: false)
    stopped = route_event_at!(Time.utc(2026, 7, 22, 12, 0))

    expect(matched_routes(stopped)).to eq([first])
    expect(stopped.reload).to be_suppressed_routing_state
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
    webhook_route = create_route!(receiver: webhook_receiver, position: 1, continue: true)
    email_route = create_route!(receiver: email_receiver, position: 2)

    event = emit_incident!
    deliveries = event.event_deliveries.order(:id)

    expect(event.reload).to be_routed_routing_state
    expect(matched_routes(event)).to eq([webhook_route, email_route])
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

    event = nil

    expect do
      event = emit_incident!
    end.to change(Event, :count).by(1)

    delivery = event.event_deliveries.sole
    expect(event.reload).to be_suppressed_routing_state
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
    event = nil

    expect do
      event = emit_incident!
    end.to change(Event, :count).by(1)

    delivery = event.event_deliveries.sole
    expect(event.reload).to be_suppressed_routing_state
    expect(matched_routes(event)).to eq([route])
    expect(delivery).to be_skipped_state
    expect(delivery.error_summary).to include('does not notify')
    expect(route.reload.hit_count).to eq(1)
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
      field: 'subject_relation',
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
    expect(matched_routes(routed_event)).to include(route)
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
    route = create_route!(
      user: SpecSeed.admin,
      receiver:,
      position: EventRoute::DEFAULT_ROUTE_POSITION,
      event_type: nil,
      subject_scope: :self
    )
    route.event_route_matchers.create!(
      field: EventRoute::DEFAULT_ROUTE_MATCHER_FIELD,
      operator: EventRoute::DEFAULT_ROUTE_MATCHER_OPERATOR,
      value: EventRoute::DEFAULT_ROUTE_MATCHER_VALUE
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
      field: 'roles',
      operator: 'contains',
      value: 'account'
    )

    event = VpsAdmin::API::Events.emit!(
      'user.suspended',
      user: SpecSeed.user,
      subject: 'Spec suspended user',
      payload: {
        'state' => 'suspended',
        'roles' => %w[account]
      }
    )
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_routed_routing_state
    expect(matched_routes(event)).to eq([route])
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
      field: 'roles',
      operator: 'not_contains',
      value: 'account'
    )

    event = VpsAdmin::API::Events.emit!(
      'user.suspended',
      user: SpecSeed.user,
      subject: 'Spec suspended user',
      payload: {
        'roles' => %w[admin]
      }
    )

    expect(event.reload).to be_routed_routing_state
    expect(matched_routes(event)).to eq([route])
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
      field: 'codename',
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
      field: 'cgroup',
      operator: '=*',
      value: '/user.slice/*.scope'
    )

    event = VpsAdmin::API::Events.emit!(
      'vps.oom_report',
      user: SpecSeed.user,
      subject: 'Spec OOM',
      payload: {
        'cgroup' => '/user.slice/a.scope'
      }
    )

    expect(event.reload).to be_routed_routing_state
    expect(event.event_deliveries.sole.target_value).to eq('audit@example.test')
  end

  it 'parses typed matcher values before comparison' do
    integer_matcher = build_matcher(
      event_type: 'vps.oom_report',
      field: 'count',
      operator: '>=',
      value: '10'
    )
    number_matcher = build_matcher(
      event_type: 'lifetime.expiration_warning',
      field: 'expires_in_days',
      operator: '>',
      value: '2.5'
    )
    datetime_matcher = build_matcher(
      event_type: 'transaction_chain.state_changed',
      field: 'changed_at',
      operator: '>=',
      value: '2026-07-01T12:00:00Z'
    )
    boolean_matcher = build_matcher(
      event_type: 'transaction_chain.state_changed',
      field: 'terminal',
      operator: '==',
      value: 'yes'
    )
    integer_list_contains_matcher = build_matcher(
      event_type: 'transaction_chain.state_changed',
      field: 'concern_object_ids',
      operator: 'contains',
      value: '42'
    )
    integer_list_not_contains_matcher = build_matcher(
      event_type: 'transaction_chain.state_changed',
      field: 'concern_object_ids',
      operator: 'not_contains',
      value: '99'
    )

    expect(integer_matcher).to be_matches(
      build_event(
        event_type: 'vps.oom_report',
        payload: { 'count' => 10 }
      )
    )
    expect(number_matcher).to be_matches(
      build_event(
        event_type: 'lifetime.expiration_warning',
        payload: { 'expires_in_days' => 3.5 }
      )
    )
    expect(datetime_matcher).to be_matches(
      build_event(
        event_type: 'transaction_chain.state_changed',
        payload: { 'changed_at' => '2026-07-01T13:00:00Z' }
      )
    )
    expect(boolean_matcher).to be_matches(
      build_event(
        event_type: 'transaction_chain.state_changed',
        payload: { 'terminal' => true }
      )
    )
    expect(integer_list_contains_matcher).to be_matches(
      build_event(
        event_type: 'transaction_chain.state_changed',
        payload: { 'concern_object_ids' => [41, 42] }
      )
    )
    expect(integer_list_not_contains_matcher).to be_matches(
      build_event(
        event_type: 'transaction_chain.state_changed',
        payload: { 'concern_object_ids' => [41, 42] }
      )
    )
  end

  it 'fails typed matcher comparisons closed when matcher values cannot be parsed' do
    integer_matcher = build_matcher(
      event_type: 'vps.oom_report',
      field: 'count',
      operator: '>=',
      value: 'ten'
    )
    datetime_matcher = build_matcher(
      event_type: 'transaction_chain.state_changed',
      field: 'changed_at',
      operator: '>=',
      value: 'yesterday'
    )
    integer_list_matcher = build_matcher(
      event_type: 'transaction_chain.state_changed',
      field: 'concern_object_ids',
      operator: 'contains',
      value: 'forty-two'
    )

    expect(integer_matcher).not_to be_matches(
      build_event(
        event_type: 'vps.oom_report',
        payload: { 'count' => 10 }
      )
    )
    expect(datetime_matcher).not_to be_matches(
      build_event(
        event_type: 'transaction_chain.state_changed',
        payload: { 'changed_at' => '2026-07-01T13:00:00Z' }
      )
    )
    expect(integer_list_matcher).not_to be_matches(
      build_event(
        event_type: 'transaction_chain.state_changed',
        payload: { 'concern_object_ids' => [42] }
      )
    )
  end

  it 'validates route grouping fields against the selected event type' do
    exact = described_class.new(
      user: SpecSeed.user,
      event_type: 'vps.oom_report',
      grouping_enabled: true,
      group_by: %w[vps_id cgroup],
      group_wait_seconds: 60,
      group_interval_seconds: 10_800
    )
    wildcard = described_class.new(
      user: SpecSeed.user,
      event_type_pattern: 'vps.*',
      grouping_enabled: true,
      group_by: ['vps_id'],
      group_wait_seconds: 60,
      group_interval_seconds: 10_800
    )
    list_field = described_class.new(
      user: SpecSeed.user,
      event_type: 'transaction_chain.state_changed',
      grouping_enabled: true,
      group_by: ['concern_object_ids'],
      group_wait_seconds: 60,
      group_interval_seconds: 10_800
    )

    expect(exact).to be_valid
    expect(wildcard).not_to be_valid
    expect(wildcard.errors[:group_by]).to include(
      'vps_id is not common to every selected event type'
    )
    expect(list_field).not_to be_valid
    expect(list_field.errors[:group_by]).to include(
      'concern_object_ids is a list field'
    )
  end

  it 'requires complete bounded grouping configuration without a template override' do
    route = described_class.new(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      grouping_enabled: true,
      group_by: %w[severity severity],
      group_wait_seconds: EventRoute::MAX_GROUP_WAIT_SECONDS + 1,
      group_interval_seconds: EventRoute::MIN_GROUP_INTERVAL_SECONDS - 1,
      template_name: 'spec_override'
    )

    expect(route).not_to be_valid
    expect(route.errors[:group_by]).to include('cannot contain duplicate fields')
    expect(route.errors[:group_wait_seconds]).to be_present
    expect(route.errors[:group_interval_seconds]).to be_present
    expect(route.errors[:template_name]).to include(
      'cannot be overridden on a grouped route'
    )
  end

  it 'rejects events with a VPS that belongs to another user' do
    vps = build_standalone_vps_fixture(user: SpecSeed.other_user).fetch(:vps)

    expect do
      emit_incident!(user: SpecSeed.user, vps:)
    end.to raise_error(ArgumentError, /VPS owner/)

    expect(Event.where(vps:)).to be_empty
  end
end
