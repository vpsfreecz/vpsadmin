# frozen_string_literal: true

require 'spec_helper'
require_relative '../../db/migrate/20260615110000_add_events'

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
    EventDelivery.delete_all
    Event.delete_all
    EventRouteMatcher.delete_all
    NotificationReceiverAction.delete_all
    NotificationTarget.delete_all
    EventRoute.delete_all
    NotificationReceiver.delete_all
  end

  def reset_advanced_mail_settings!
    UserNotificationTemplateRecipient.delete_all
    UserEmailRoleRecipient.delete_all
  end

  def run_events_migration_backfill!
    verbose = ActiveRecord::Migration.verbose
    reset_all_event_routing!
    migration = AddEvents.new
    ActiveRecord::Migration.verbose = false
    migration.send(:backfill_default_routes)
    migration.send(:backfill_advanced_mail_routes)
  ensure
    ActiveRecord::Migration.verbose = verbose
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

  it 'backfills template recipient overrides into explicit e-mail routes' do
    reset_advanced_mail_settings!
    template = event_notification_template!('vps_incident_report')
    UserNotificationTemplateRecipient.create!(
      user: SpecSeed.user,
      notification_template: template,
      to: 'incident-override@example.test',
      enabled: true
    )

    run_events_migration_backfill!

    event = emit_incident!
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route.position).to eq(10)
    expect(delivery.action).to eq('email')
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('incident-override@example.test')
    expect(delivery.template_name).to eq('vps_incident_report')
  end

  it 'backfills parameterized expiration template recipient overrides' do
    reset_advanced_mail_settings!
    template = event_notification_template!('expiration_vps_active')
    template.update!(template_id: 'expiration_warning')
    UserNotificationTemplateRecipient.create!(
      user: SpecSeed.user,
      notification_template: template,
      to: 'expiration-override@example.test',
      enabled: true
    )
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)

    run_events_migration_backfill!

    event = VpsAdmin::API::Events.emit!(
      'lifetime.expiration_warning',
      user: SpecSeed.user,
      vps:,
      source: vps,
      subject: 'Spec VPS expiration',
      parameters: {
        object: 'vps',
        object_id: vps.id,
        object_label: vps.hostname,
        state: 'active'
      }
    )
    delivery = event.event_deliveries.sole
    matchers = event.matched_event_route.event_route_matchers.order(:id)

    expect(event.reload).to be_routed_routing_state
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('expiration-override@example.test')
    expect(delivery.template_name).to eq('expiration_warning')
    expect(matchers.map { |m| [m.field, m.operator, m.value] }).to eq(
      [
        ['parameters.object', '==', 'vps'],
        ['parameters.state', '==', 'active']
      ]
    )
  end

  it 'backfills payment accepted template recipient overrides' do
    reset_advanced_mail_settings!
    template = event_notification_template!('payment_accepted')
    UserNotificationTemplateRecipient.create!(
      user: SpecSeed.user,
      notification_template: template,
      to: 'payment-override@example.test',
      enabled: true
    )

    run_events_migration_backfill!

    event = VpsAdmin::API::Events.emit!(
      'payment.accepted',
      user: SpecSeed.user,
      subject: 'Spec payment accepted',
      parameters: {
        payment_id: 123,
        received_amount: 200,
        received_currency: 'CZK'
      }
    )
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route.event_type).to eq('payment.accepted')
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('payment-override@example.test')
    expect(delivery.template_name).to eq('payment_accepted')
  end

  it 'backfills outage update template overrides for all update events' do
    reset_advanced_mail_settings!
    template = event_notification_template!('outage_report_user_update')
    UserNotificationTemplateRecipient.create!(
      user: SpecSeed.user,
      notification_template: template,
      to: 'outage-update@example.test',
      enabled: true
    )

    run_events_migration_backfill!

    event = VpsAdmin::API::Events.emit!(
      'outage.updated',
      user: SpecSeed.user,
      subject: 'Spec outage resolved',
      parameters: {
        role: 'user',
        event: 'resolve',
        outage_id: 123,
        update_id: 456
      }
    )
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route.event_type).to eq('outage.updated')
    expect(event.matched_event_route.event_route_matchers.map(&:summary)).to contain_exactly(
      'parameters.role == user'
    )
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('outage-update@example.test')
    expect(delivery.template_name).to eq('outage_report_role_event')
  end

  it 'backfills request template overrides in fallback order' do
    reset_advanced_mail_settings!
    specific = event_notification_template!('request_resolve_user_change_approved')
    specific.update!(template_id: 'request_resolve_role_type_state')
    generic = event_notification_template!('request_resolve_user')
    generic.update!(template_id: 'request_action_role')
    UserNotificationTemplateRecipient.create!(
      user: SpecSeed.user,
      notification_template: generic,
      to: 'request-generic@example.test',
      enabled: true
    )
    UserNotificationTemplateRecipient.create!(
      user: SpecSeed.user,
      notification_template: specific,
      to: 'request-specific@example.test',
      enabled: true
    )

    run_events_migration_backfill!

    event = VpsAdmin::API::Events.emit!(
      'request.resolved',
      user: SpecSeed.user,
      subject: 'Spec request resolved',
      parameters: {
        role: 'user',
        action: 'resolve',
        request_type: 'change',
        request_state: 'approved',
        request_id: 123,
        mail_id: 2
      }
    )
    delivery = event.event_deliveries.sole
    matchers = event.matched_event_route.event_route_matchers.order(:id)

    expect(event.reload).to be_routed_routing_state
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('request-specific@example.test')
    expect(delivery.template_name).to eq('request_resolve_role_type_state')
    expect(matchers.map { |m| [m.field, m.operator, m.value] }).to eq(
      [
        ['parameters.role', '==', 'user'],
        ['parameters.request_type', '==', 'change'],
        ['parameters.request_state', '==', 'approved']
      ]
    )
  end

  it 'backfills role recipients behind template-specific routes' do
    reset_advanced_mail_settings!
    UserEmailRoleRecipient.create!(
      user: SpecSeed.user,
      role: 'admin',
      to: 'admin-role@example.test'
    )

    run_events_migration_backfill!

    event = VpsAdmin::API::Events.emit!(
      'vps.oom_prevention',
      user: SpecSeed.user,
      subject: 'Spec OOM prevention',
      parameters: {
        'action' => 'restart'
      }
    )
    delivery = event.event_deliveries.sole
    storage_event = VpsAdmin::API::Events.emit!(
      'vps.dataset_expanded',
      user: SpecSeed.user,
      subject: 'Spec dataset expanded',
      parameters: {
        'added_space' => 1024
      }
    )
    storage_delivery = storage_event.event_deliveries.sole
    oom_report_route = described_class.find_by!(
      user: SpecSeed.user,
      event_type: 'vps.oom_report',
      label: 'System administrator e-mail for OOM report'
    )

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route.position).to be >= 1_000
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('admin-role@example.test')
    expect(delivery.template_name).to eq('vps_oom_prevention')
    expect(storage_event.reload).to be_routed_routing_state
    expect(storage_delivery.target_value).to eq('admin-role@example.test')
    expect(storage_delivery.template_name).to eq('vps_dataset_expanded')
    expect(
      oom_report_route.event_route_matchers.map { |m| [m.field, m.operator, m.value] }
    ).to eq(
      [
        ['parameters.stage', '==', 'notification']
      ]
    )
  end

  it 'backfills account role recipients for user account events' do
    reset_advanced_mail_settings!
    UserEmailRoleRecipient.create!(
      user: SpecSeed.user,
      role: 'account',
      to: 'account-role@example.test'
    )

    run_events_migration_backfill!

    event = VpsAdmin::API::Events.emit!(
      'user.suspended',
      user: SpecSeed.user,
      subject: 'Spec suspended user',
      parameters: {
        'state' => 'suspended'
      }
    )
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route.position).to be >= 1_000
    expect(event.matched_event_route.label).to eq('Account management e-mail for User account suspended')
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('account-role@example.test')
    expect(delivery.template_name).to eq('user_suspend')
  end

  it 'backfills all matching role recipients for multi-role templates' do
    reset_advanced_mail_settings!
    UserEmailRoleRecipient.create!(
      user: SpecSeed.user,
      role: 'account',
      to: 'account-role@example.test'
    )
    UserEmailRoleRecipient.create!(
      user: SpecSeed.user,
      role: 'admin',
      to: 'admin-role@example.test'
    )

    run_events_migration_backfill!

    event = VpsAdmin::API::Events.emit!(
      'vps.suspended',
      user: SpecSeed.user,
      subject: 'Spec suspended VPS',
      parameters: {
        'state' => 'suspended'
      }
    )
    deliveries = event.event_deliveries.order(:id)
    account_route = described_class.find_by!(
      user: SpecSeed.user,
      event_type: 'vps.suspended',
      label: 'Account management e-mail for VPS suspended'
    )
    admin_route = described_class.find_by!(
      user: SpecSeed.user,
      event_type: 'vps.suspended',
      label: 'System administrator e-mail for VPS suspended'
    )

    expect(event.reload).to be_routed_routing_state
    expect(account_route).to be_continue
    expect(admin_route).not_to be_continue
    expect(deliveries.map(&:target_value)).to eq(
      %w[account-role@example.test admin-role@example.test]
    )
    expect(deliveries.map(&:template_name)).to eq(%w[vps_suspend vps_suspend])
  end

  it 'backfills disabled OOM template recipients only for notification events' do
    reset_advanced_mail_settings!
    template = event_notification_template!('vps_oom_report')
    UserNotificationTemplateRecipient.create!(
      user: SpecSeed.user,
      notification_template: template,
      to: '',
      enabled: false
    )

    run_events_migration_backfill!

    muted_route = described_class.find_by!(
      user: SpecSeed.user,
      event_type: 'vps.oom_report',
      label: "#{template.label} disabled"
    )
    notification_event = emit_oom_report!('notification')
    raw_event = emit_oom_report!('raw')

    expect(notification_event.reload).to be_suppressed_routing_state
    expect(notification_event.matched_event_route).to eq(muted_route)
    expect(notification_event.event_deliveries.sole).to be_skipped_state
    expect(raw_event.reload).to be_routed_routing_state
    expect(raw_event.matched_event_route).not_to eq(muted_route)
    expect(muted_route.reload.hit_count).to eq(1)
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
