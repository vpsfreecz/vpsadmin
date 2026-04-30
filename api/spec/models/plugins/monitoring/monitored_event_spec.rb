# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'monitoring monitored event model', requires_plugins: :monitoring do # rubocop:disable RSpec/DescribeClass
  let(:obj) { SpecSeed.user }
  let(:user) { SpecSeed.admin }

  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def monitor(name = :spec_event_monitor, **opts)
    build_monitor(name, check_count: 1, **opts)
  end

  def create_event(mon, state:, **attrs)
    MonitoredEvent.create!({
      monitor_name: mon.name,
      class_name: obj.class.name,
      row_id: obj.id,
      state: state,
      user: user,
      access_level: 0
    }.merge(attrs))
  end

  def with_registered_monitor(mon)
    allow(VpsAdmin::API::Plugins::Monitoring).to receive(:monitors).and_return([mon])
    yield
  end

  before do
    allow(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert).to receive(:fire)
  end

  it 'creates and confirms a new event when a failing check reaches the threshold' do
    mon = monitor(:first_failure)

    MonitoredEvent.report!(mon, obj, 'bad', false, user)

    event = MonitoredEvent.find_by!(monitor_name: 'first_failure')
    expect(event.state).to eq('confirmed')
    expect(event.monitored_event_logs.last.value).to eq('bad')
    expect(event.monitored_event_states.pluck(:state)).to include('confirmed')
    expect(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert)
      .to have_received(:fire).with(event)
  end

  it 'does not create an event for passing checks' do
    MonitoredEvent.report!(monitor(:passing), obj, 'ok', true, user)

    expect(MonitoredEvent.exists?(monitor_name: 'passing')).to be(false)
    expect(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert).not_to have_received(:fire)
  end

  it 'suppresses new events during cooldown after a recent close' do
    mon = monitor(:cooldown, cooldown: 1.hour)
    create_event(mon, state: :closed, updated_at: 5.minutes.ago)

    MonitoredEvent.report!(mon, obj, 'bad', false, user)

    expect(MonitoredEvent.where(monitor_name: 'cooldown').count).to eq(1)
    expect(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert).not_to have_received(:fire)
  end

  it 'reverts saved acknowledged and ignored events to confirmed after saved_until expires' do
    ack_monitor = monitor(:saved_ack, skip_acknowledged: false)
    ignored_monitor = monitor(:saved_ignored, skip_ignored: false)
    ack = create_event(ack_monitor, state: :acknowledged, saved_until: 1.minute.ago)
    ignored = create_event(ignored_monitor, state: :ignored, saved_until: 1.minute.ago)

    with_registered_monitor(ack_monitor) do
      MonitoredEvent.report!(ack_monitor, obj, 'bad', false, user)
    end
    with_registered_monitor(ignored_monitor) do
      MonitoredEvent.report!(ignored_monitor, obj, 'bad', false, user)
    end

    expect(ack.reload.state).to eq('confirmed')
    expect(ack.saved_until).to be_nil
    expect(ignored.reload.state).to eq('confirmed')
    expect(ignored.saved_until).to be_nil
  end

  it 'honors skip_ignored and skip_acknowledged without reporting alerts' do
    ignored_monitor = monitor(:skip_ignored, skip_ignored: true)
    ack_monitor = monitor(:skip_ack, skip_acknowledged: true)
    ignored = create_event(ignored_monitor, state: :ignored, saved_until: 1.hour.from_now)
    acknowledged = create_event(ack_monitor, state: :acknowledged, saved_until: 1.hour.from_now)

    with_registered_monitor(ignored_monitor) do
      MonitoredEvent.report!(ignored_monitor, obj, 'bad', false, user)
    end
    with_registered_monitor(ack_monitor) do
      MonitoredEvent.report!(ack_monitor, obj, 'bad', false, user)
    end

    expect(ignored.reload.state).to eq('ignored')
    expect(ignored.monitored_event_logs.count).to eq(0)
    expect(acknowledged.reload.state).to eq('acknowledged')
    expect(acknowledged.monitored_event_logs.count).to eq(1)
    expect(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert).not_to have_received(:fire)
  end

  it 'moves passing monitoring events to unconfirmed and closes confirmed events' do
    raw_monitor = monitor(:raw_pass)
    confirmed_monitor = monitor(:confirmed_pass)
    raw = create_event(raw_monitor, state: :monitoring)
    confirmed = create_event(confirmed_monitor, state: :confirmed, last_report_at: 1.hour.ago)

    MonitoredEvent.report!(raw_monitor, obj, 'ok', true, user)
    MonitoredEvent.report!(confirmed_monitor, obj, 'ok', true, user)

    expect(raw.reload.state).to eq('unconfirmed')
    expect(confirmed.reload.state).to eq('closed')
    expect(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert)
      .to have_received(:fire).with(confirmed)
  end

  it 'fires repeat alerts after the repeat interval elapses' do
    mon = monitor(:repeat_alert, repeat: 10.minutes)
    event = create_event(mon, state: :confirmed, last_report_at: 30.minutes.ago)

    MonitoredEvent.report!(mon, obj, 'bad again', false, user)

    expect(event.reload.last_report_at).to be > 5.minutes.ago
    expect(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert)
      .to have_received(:fire).with(event)
  end

  it 'fires the alert chain only after the configured check count is reached' do
    mon = monitor(:check_count_alert, check_count: 2)

    MonitoredEvent.report!(mon, obj, 'bad-1', false, user)
    expect(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert).not_to have_received(:fire)

    event = MonitoredEvent.find_by!(monitor_name: 'check_count_alert')
    MonitoredEvent.report!(mon, obj, 'bad-2', false, user)

    expect(event.reload.state).to eq('confirmed')
    expect(VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert)
      .to have_received(:fire).with(event)
  end
end
