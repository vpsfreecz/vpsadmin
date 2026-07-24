# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventDeliveryGroup do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    allow(NotificationTemplate).to receive(:send_custom_email)
      .and_return(build_mail_log_double)
    allow(VpsAdmin::API::Notifications).to receive_messages(
      telegram_configured?: true,
      sms_configured?: true
    )
  end

  def create_grouped_route!(actions: [:webhook], group_by: ['severity'],
                            group_wait_seconds: 10, group_interval_seconds: 300)
    receiver = NotificationReceiver.create!(
      user: SpecSeed.user,
      label: 'Grouped spec receiver'
    )

    actions.each do |action|
      SpecSeed.user.set_notification_delivery_method!(action, true)
      attrs = {
        action:,
        label: "Grouped #{action}",
        target_kind: action == :email ? :default_recipient : :custom,
        target_value: group_target(action)
      }
      attrs[:secret] = 'grouped-webhook-secret' if action == :webhook
      attrs[:verified_at] = Time.now if %i[telegram sms].include?(action)
      receiver.notification_receiver_actions.create!(attrs)
    end

    route = EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'user.test_notification',
      grouping_enabled: true,
      group_by:,
      group_wait_seconds:,
      group_interval_seconds:
    )

    [route, receiver]
  end

  def group_target(action)
    {
      webhook: 'https://webhook.example/grouped',
      telegram: '123456789',
      sms: '+420123456789'
    }[action]
  end

  def emit_grouped_event!(subject:, severity: :info, release: true)
    VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject:,
      severity:,
      payload: { note: subject },
      release:
    )
  end

  def activate!(delivery, released_at:)
    delivery.update_columns(
      state: EventDelivery.states.fetch('released'),
      released_at:,
      next_attempt_at: released_at,
      updated_at: released_at
    )
    VpsAdmin::API::Notifications::GroupActivation.activate!(
      delivery.reload,
      now: released_at
    )
  end

  let(:publisher) { instance_double(VpsAdmin::API::Notifications::Publisher, publish_after_commit: nil) }

  it 'waits for the first batch and seals matching members into one delivery' do
    create_grouped_route!
    first = emit_grouped_event!(subject: 'First grouped event').event_deliveries.sole
    second = emit_grouped_event!(subject: 'Second grouped event').event_deliveries.sole
    started_at = Time.utc(2026, 7, 24, 12, 0, 0)

    first_group = activate!(first, released_at: started_at)
    second_group = activate!(second, released_at: started_at + 2)

    expect(second_group).to eq(first_group)
    expect(first_group.reload.next_flush_at).to eq(started_at + 10)
    expect(
      VpsAdmin::API::Notifications::GroupSealer.seal!(
        first_group,
        now: started_at + 9,
        publisher:
      )
    ).to be_nil

    leader = VpsAdmin::API::Notifications::GroupSealer.seal!(
      first_group,
      now: started_at + 10,
      publisher:
    )

    expect(leader).to eq(first)
    expect(first.reload).to be_released_state
    expect(second.reload).to be_grouped_state
    expect(second.effective_event_delivery_id).to eq(first.id)
    expect(first.event_count).to eq(2)

    payload = JSON.parse(first.payload)
    expect(payload).to include('version' => 1)
    expect(payload.dig('group', 'grouped')).to be(true)
    expect(payload.dig('group', 'event_count')).to eq(2)
    expect(payload.fetch('events').map { |event| event.fetch('id') })
      .to eq([first.event_id, second.event_id])
    expect(
      VpsAdmin::API::Notifications::GroupSealer.seal!(
        first_group,
        now: started_at + 10,
        publisher:
      )
    ).to be_nil
  end

  it 'uses group_interval to delay a later batch for the same labels' do
    create_grouped_route!
    first = emit_grouped_event!(subject: 'First interval event').event_deliveries.sole
    started_at = Time.utc(2026, 7, 24, 12, 0, 0)
    group = activate!(first, released_at: started_at)
    VpsAdmin::API::Notifications::GroupSealer.seal!(
      group,
      now: started_at + 10,
      publisher:
    )

    later = emit_grouped_event!(subject: 'Later interval event').event_deliveries.sole
    group = activate!(later, released_at: started_at + 20)

    expect(group.reload.next_flush_at).to eq(started_at + 310)
    expect(later.reload).to be_grouping_state
  end

  it 'creates distinct groups for different label values' do
    create_grouped_route!
    info = emit_grouped_event!(subject: 'Info event', severity: :info).event_deliveries.sole
    warning = emit_grouped_event!(subject: 'Warning event', severity: :warning).event_deliveries.sole
    started_at = Time.utc(2026, 7, 24, 12, 0, 0)

    info_group = activate!(info, released_at: started_at)
    warning_group = activate!(warning, released_at: started_at)

    expect(info.group_key).not_to eq(warning.group_key)
    expect(info_group).not_to eq(warning_group)
    expect(info_group.labels).to eq('severity' => 'info')
    expect(warning_group.labels).to eq('severity' => 'warning')
  end

  it 'recovers when another dispatcher creates the group concurrently' do
    create_grouped_route!
    delivery = emit_grouped_event!(subject: 'Concurrent group creation').event_deliveries.sole
    calls = 0

    allow(described_class)
      .to receive(:find_or_create_by!)
      .and_wrap_original do |method, *args, &block|
        calls += 1
        raise ActiveRecord::RecordNotUnique if calls == 1

        method.call(*args, &block)
      end

    group = activate!(delivery, released_at: Time.utc(2026, 7, 24, 12, 0, 0))

    expect(calls).to eq(2)
    expect(group).to be_persisted
    expect(delivery.reload.event_delivery_group).to eq(group)
  end

  it 'separates groups when the snapshotted destination changes' do
    _route, receiver = create_grouped_route!
    first = emit_grouped_event!(subject: 'Original destination').event_deliveries.sole
    receiver.notification_receiver_actions.sole.update!(
      target_value: 'https://changed.example/grouped'
    )
    second = emit_grouped_event!(subject: 'Changed destination').event_deliveries.sole

    expect(first.target_value).to eq('https://webhook.example/grouped')
    expect(second.target_value).to eq('https://changed.example/grouped')
    expect(first.target_secret).to eq('grouped-webhook-secret')
    expect(first.group_key).not_to eq(second.group_key)
  end

  it 'does not release grouped members before transaction release' do
    create_grouped_route!
    delivery = emit_grouped_event!(
      subject: 'Transaction-gated event',
      release: false
    ).event_deliveries.sole

    expect(delivery).to be_prepared_state
    expect(
      VpsAdmin::API::Notifications::GroupActivation.activate!(delivery)
    ).to be_nil

    VpsAdmin::API::Notifications::Release.release!(delivery, publisher:)
    group = VpsAdmin::API::Notifications::GroupActivation.activate!(delivery.reload)

    expect(group).to be_present
    expect(delivery.reload).to be_grouping_state
  end

  it 'keeps muted events out of delivery groups' do
    receiver = NotificationReceiver.create!(
      user: SpecSeed.user,
      label: 'Grouped mute',
      mute: true
    )
    EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'user.test_notification',
      grouping_enabled: true,
      group_by: ['severity'],
      group_wait_seconds: 10,
      group_interval_seconds: 300
    )

    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Muted grouped event',
      persist: :always
    )
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_suppressed_routing_state
    expect(delivery).to be_skipped_state
    expect(delivery.group_key).to be_nil
    expect(described_class.count).to eq(0)
  end

  it 'prepares grouped snapshots for every notification action' do
    create_grouped_route!(
      actions: %i[email webhook telegram sms],
      group_by: [],
      group_wait_seconds: 0,
      group_interval_seconds: 60
    )
    deliveries = emit_grouped_event!(subject: 'All actions event').event_deliveries.order(:id).to_a
    now = Time.now

    leaders = deliveries.map do |delivery|
      group = activate!(delivery, released_at: now)
      VpsAdmin::API::Notifications::GroupSealer.seal!(
        group,
        now:,
        publisher:
      )
    end

    expect(leaders.map(&:action)).to contain_exactly('email', 'webhook', 'telegram', 'sms')
    expect(leaders.map { |delivery| delivery.reload.state }).to all(eq('released'))
    expect(leaders.detect(&:email_action?).mail_log).to be_present
    webhook = leaders.detect(&:webhook_action?)
    expect(JSON.parse(webhook.payload)).to include('version' => 1)
    webhook_headers = VpsAdmin::API::Notifications::Dispatcher
                      .new('webhook')
                      .send(:webhook_headers, webhook, webhook.payload)
    expect(webhook_headers).to include(
      'X-VpsAdmin-Event' => 'user.test_notification',
      'X-VpsAdmin-Group' => webhook.event_delivery_group.group_key
    )
    expect(JSON.parse(leaders.detect(&:telegram_action?).payload))
      .to include('chat_id' => '123456789')
    expect(JSON.parse(leaders.detect(&:sms_action?).payload))
      .to include('to' => '+420123456789')
  end

  it 'keeps a sealed payload immutable while later events form another batch' do
    create_grouped_route!
    first = emit_grouped_event!(subject: 'Immutable first event').event_deliveries.sole
    started_at = Time.utc(2026, 7, 24, 12, 0, 0)
    group = activate!(first, released_at: started_at)
    leader = VpsAdmin::API::Notifications::GroupSealer.seal!(
      group,
      now: started_at + 10,
      publisher:
    )
    sealed_payload = leader.payload

    later = emit_grouped_event!(subject: 'Next batch event').event_deliveries.sole
    activate!(later, released_at: started_at + 20)
    leader.update!(state: :failed, error_summary: 'spec transport failure')

    VpsAdmin::API::Notifications::Retry.retry!(leader, publisher:)

    expect(leader.reload.payload).to eq(sealed_payload)
    expect(JSON.parse(leader.payload).fetch('events').length).to eq(1)
    expect(later.reload).to be_grouping_state
    expect(later.effective_event_delivery_id).to be_nil
  end
end
