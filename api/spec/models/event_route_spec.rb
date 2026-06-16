# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventRoute do
  before do
    reset_routing!(SpecSeed.user)
  end

  def reset_routing!(user, mailer_enabled: true)
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    EventRoute.where(user:).delete_all
    NotificationReceiver.where(user:).delete_all
    user.update!(mailer_enabled:)
  end

  def emit_incident!(user: SpecSeed.user, vps: nil, codename: 'Spec-Abuse')
    VpsAdmin::API::Events.emit!(
      'vps.incident_report',
      user:,
      vps:,
      subject: 'Spec incident',
      summary: 'Spec incident summary',
      parameters: {
        'codename' => codename,
        'subject' => 'Spec incident',
        'text' => 'Spec incident body'
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

  it 'creates and uses the default e-mail receiver when no routes exist' do
    event = emit_incident!
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_routed_routing_state
    expect(event.matched_event_route).to be_present
    expect(delivery.action).to eq('email')
    expect(delivery.target_kind).to eq('default_recipient')
    expect(delivery.target_label).to eq(SpecSeed.user.email)
    expect(delivery.template_name).to eq('vps_incident_report')
    expect(delivery).to be_planned_state
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
    expect(deliveries.first).to be_queued_state
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
    receiver = create_receiver!(
      label: 'Webhook receiver',
      action: {
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events'
      }
    )
    create_route!(receiver:, position: 1, continue: true)
    create_route!(receiver:, position: 2)

    event = emit_incident!
    deliveries = event.event_deliveries.to_a

    expect(deliveries.count).to eq(1)
    expect(deliveries.first.action).to eq('webhook')
    expect(deliveries.first.target_value).to eq('https://example.test/events')
  end

  it 'suppresses events through a mute receiver' do
    receiver = create_receiver!(label: 'Do not notify', mute: true)
    route = create_route!(receiver:)

    event = emit_incident!
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_suppressed_routing_state
    expect(event.matched_event_route).to eq(route)
    expect(delivery).to be_skipped_state
    expect(delivery.error_summary).to eq('receiver does not notify')
  end

  it 'preserves disabled mailer users as a default mute receiver' do
    reset_routing!(SpecSeed.user, mailer_enabled: false)

    event = emit_incident!
    delivery = event.event_deliveries.sole
    receiver = SpecSeed.user.notification_receivers.sole

    expect(receiver).to be_mute
    expect(event.reload).to be_suppressed_routing_state
    expect(delivery).to be_skipped_state
    expect(delivery.notification_receiver).to eq(receiver)
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

  it 'rejects events with a VPS that belongs to another user' do
    vps = build_standalone_vps_fixture(user: SpecSeed.other_user).fetch(:vps)

    expect do
      emit_incident!(user: SpecSeed.user, vps:)
    end.to raise_error(ArgumentError, /VPS owner/)

    expect(Event.where(vps:)).to be_empty
  end
end
