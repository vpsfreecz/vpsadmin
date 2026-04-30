# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'monitoring plugin rake tasks', requires_plugins: :monitoring do # rubocop:disable RSpec/DescribeClass
  around do |example|
    with_rake_application do
      load_plugin_rake_tasks('plugins/monitoring/api/tasks/monitoring.rake')
      with_current_context(user: SpecSeed.admin) { example.run }
    end
  end

  def create_event!(state:, monitor_name: "task_#{SecureRandom.hex(4)}", created_at: Time.now, updated_at: Time.now)
    MonitoredEvent.create!(
      monitor_name: monitor_name,
      class_name: 'User',
      row_id: SpecSeed.user.id,
      state: state,
      user: SpecSeed.admin,
      access_level: 0,
      created_at: created_at,
      updated_at: updated_at
    )
  end

  it 'runs all configured monitors' do
    monitor_a = build_monitor(:task_monitor_a)
    monitor_b = build_monitor(:task_monitor_b)
    allow(monitor_a).to receive(:check)
    allow(monitor_b).to receive(:check)
    allow(VpsAdmin::API::Plugins::Monitoring).to receive(:monitors).and_return([monitor_a, monitor_b])

    invoke_rake_task('vpsadmin:monitoring:check')

    expect(monitor_a).to have_received(:check)
    expect(monitor_b).to have_received(:check)
  end

  it 'closes inactive active events older than one month' do
    old = create_event!(state: :confirmed, updated_at: 2.months.ago)
    recent = create_event!(state: :confirmed, updated_at: 1.day.ago)

    invoke_rake_task('vpsadmin:monitoring:close')

    expect(old.reload.state).to eq('closed')
    expect(recent.reload.state).to eq('confirmed')
  end

  it 'prunes old unconfirmed and closed events in batches until none remain' do
    old_time = 400.days.ago
    rows = 10_001.times.map do |i|
      {
        monitor_name: "prune_closed_#{i}",
        class_name: 'User',
        row_id: SpecSeed.user.id,
        state: MonitoredEvent.states[:closed],
        user_id: SpecSeed.admin.id,
        access_level: 0,
        created_at: old_time,
        updated_at: old_time
      }
    end
    rows << {
      monitor_name: 'prune_unconfirmed',
      class_name: 'User',
      row_id: SpecSeed.user.id,
      state: MonitoredEvent.states[:unconfirmed],
      user_id: SpecSeed.admin.id,
      access_level: 0,
      created_at: old_time,
      updated_at: old_time
    }
    MonitoredEvent.insert_all!(rows)
    keep_confirmed = create_event!(state: :confirmed, monitor_name: 'keep_confirmed', created_at: old_time)
    keep_recent = create_event!(state: :closed, monitor_name: 'keep_recent', created_at: 1.day.ago)

    out, = capture_streams do
      invoke_rake_task('vpsadmin:monitoring:prune', env: { DAYS: '365' })
    end

    expect(out).to include('Deleted 10002 monitored events')
    expect(MonitoredEvent.where("monitor_name LIKE 'prune_%'").count).to eq(0)
    expect(MonitoredEvent.exists?(keep_confirmed.id)).to be(true)
    expect(MonitoredEvent.exists?(keep_recent.id)).to be(true)
  end
end
