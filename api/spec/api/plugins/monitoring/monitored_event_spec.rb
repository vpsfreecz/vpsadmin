# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::MonitoredEvent', requires_plugins: :monitoring do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin

    # Ensure monitor definitions exist for any monitor_name used in fixtures.
    install_stub_monitors!
    fixtures
  end

  def index_path
    vpath('/monitored_events')
  end

  def show_path(id)
    vpath("/monitored_events/#{id}")
  end

  def ack_path(id)
    vpath("/monitored_events/#{id}/acknowledge")
  end

  def ignore_path(id)
    vpath("/monitored_events/#{id}/ignore")
  end

  def logs_path(event_id)
    vpath("/monitored_events/#{event_id}/logs")
  end

  def log_path(event_id, log_id)
    vpath("/monitored_events/#{event_id}/logs/#{log_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def events
    json.dig('response', 'monitored_events') || []
  end

  def event_obj
    json.dig('response', 'monitored_event') || json['response']
  end

  def logs
    json.dig('response', 'logs') || json.dig('response', 'monitored_event_logs') || []
  end

  def log_obj
    json.dig('response', 'log') || json.dig('response', 'monitored_event_log') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def install_stub_monitors!
    a = VpsAdmin::API::Plugins::Monitoring::Monitor.new(
      :spec_a,
      label: 'Spec Monitor A',
      desc: 'Spec Issue A',
      access_level: 0,
      skip_acknowledged: false,
      skip_ignored: false
    )

    b = VpsAdmin::API::Plugins::Monitoring::Monitor.new(
      :spec_b,
      label: 'Spec Monitor B',
      desc: 'Spec Issue B',
      access_level: 0,
      skip_acknowledged: false,
      skip_ignored: false
    )

    # Replace the monitor list to keep test runs deterministic.
    VpsAdmin::API::Plugins::Monitoring.instance_variable_set(:@monitors, [a, b])
  end

  let(:admin) { SpecSeed.admin }
  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }
  let(:now) { Time.now }

  # Fixtures created per-example (transaction rollback cleans up).
  def fixtures
    @fixtures ||= build_fixtures
  end

  def build_fixtures
    event_user_confirmed = ::MonitoredEvent.create!(
      monitor_name: 'spec_a',
      class_name: 'Node',
      row_id: SpecSeed.node.id,
      user: user,
      access_level: 0,
      state: 'confirmed',
      created_at: now - 3.hours,
      updated_at: now - 3.hours + 120.seconds
    )

    event_user_closed = ::MonitoredEvent.create!(
      monitor_name: 'spec_a',
      class_name: 'Node',
      row_id: SpecSeed.other_node.id,
      user: user,
      access_level: 0,
      state: 'closed',
      created_at: now - 2.hours,
      updated_at: now - 2.hours + 60.seconds
    )

    event_user_monitoring = ::MonitoredEvent.create!(
      monitor_name: 'spec_b',
      class_name: 'Node',
      row_id: SpecSeed.node.id,
      user: user,
      access_level: 0,
      state: 'monitoring',
      created_at: now - 1.hour,
      updated_at: now - 1.hour + 10.seconds
    )

    event_other_confirmed = ::MonitoredEvent.create!(
      monitor_name: 'spec_b',
      class_name: 'Node',
      row_id: SpecSeed.node.id,
      user: other_user,
      access_level: 0,
      state: 'confirmed',
      created_at: now - 4.hours,
      updated_at: now - 4.hours + 10.seconds
    )

    event_user_high_access = ::MonitoredEvent.create!(
      monitor_name: 'spec_b',
      class_name: 'Node',
      row_id: SpecSeed.node.id,
      user: user,
      access_level: 5,
      state: 'confirmed',
      created_at: now - 5.hours,
      updated_at: now - 5.hours + 10.seconds
    )

    event_admin_too_high_access = ::MonitoredEvent.create!(
      monitor_name: 'spec_a',
      class_name: 'Node',
      row_id: SpecSeed.node.id,
      user: admin,
      access_level: 100,
      state: 'confirmed',
      created_at: now - 6.hours,
      updated_at: now - 6.hours + 10.seconds
    )

    log_ok = ::MonitoredEventLog.create!(
      monitored_event: event_user_confirmed,
      passed: true,
      value: 'ok',
      created_at: now - 50.minutes
    )

    log_fail = ::MonitoredEventLog.create!(
      monitored_event: event_user_confirmed,
      passed: false,
      value: 'fail',
      created_at: now - 40.minutes
    )

    log_ok_again = ::MonitoredEventLog.create!(
      monitored_event: event_user_confirmed,
      passed: true,
      value: 'ok2',
      created_at: now - 30.minutes
    )

    log_other = ::MonitoredEventLog.create!(
      monitored_event: event_other_confirmed,
      passed: false,
      value: 'other',
      created_at: now - 20.minutes
    )

    {
      event_user_confirmed: event_user_confirmed,
      event_user_closed: event_user_closed,
      event_user_monitoring: event_user_monitoring,
      event_other_confirmed: event_other_confirmed,
      event_user_high_access: event_user_high_access,
      event_admin_too_high_access: event_admin_too_high_access,
      log_ok: log_ok,
      log_fail: log_fail,
      log_ok_again: log_ok_again,
      log_other: log_other
    }
  end

  def event_user_confirmed
    fixtures.fetch(:event_user_confirmed)
  end

  def event_user_closed
    fixtures.fetch(:event_user_closed)
  end

  def event_user_monitoring
    fixtures.fetch(:event_user_monitoring)
  end

  def event_other_confirmed
    fixtures.fetch(:event_other_confirmed)
  end

  def event_user_high_access
    fixtures.fetch(:event_user_high_access)
  end

  def event_admin_too_high_access
    fixtures.fetch(:event_admin_too_high_access)
  end

  def log_ok
    fixtures.fetch(:log_ok)
  end

  def log_fail
    fixtures.fetch(:log_fail)
  end

  def log_ok_again
    fixtures.fetch(:log_ok_again)
  end

  def log_other
    fixtures.fetch(:log_other)
  end

  describe 'API description' do
    it 'includes monitored_event endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'monitored_event#index',
        'monitored_event#show',
        'monitored_event#acknowledge',
        'monitored_event#ignore',
        'monitored_event.log#index',
        'monitored_event.log#show'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to see own events in allowed states and within access level' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = events.map { |row| row['id'] }
      expect(ids).to include(event_user_confirmed.id, event_user_closed.id)
      expect(ids).not_to include(
        event_user_monitoring.id,
        event_other_confirmed.id,
        event_user_high_access.id
      )
    end

    it 'does not allow users to filter by user param' do
      as(user) { json_get index_path, monitored_event: { user: other_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(event_user_confirmed.id, event_user_closed.id)
    end

    it 'allows admin to see all events within access level' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = events.map { |row| row['id'] }
      expect(ids).to include(
        event_user_confirmed.id,
        event_user_closed.id,
        event_user_monitoring.id,
        event_other_confirmed.id,
        event_user_high_access.id
      )
      expect(ids).not_to include(event_admin_too_high_access.id)
    end

    it 'supports admin filters' do
      as(admin) { json_get index_path, monitored_event: { monitor: 'spec_b' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(events.map { |row| row['monitor'] }.uniq).to eq(['spec_b'])

      as(admin) do
        json_get index_path, monitored_event: {
          object_name: 'Node',
          object_id: SpecSeed.node.id
        }
      end

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to include(
        event_user_confirmed.id,
        event_user_monitoring.id,
        event_other_confirmed.id,
        event_user_high_access.id
      )
      expect(ids).not_to include(event_user_closed.id)

      as(admin) { json_get index_path, monitored_event: { state: 'closed' } }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(event_user_closed.id)
    end

    it 'orders by latest and oldest' do
      as(admin) { json_get index_path, monitored_event: { order: 'latest' } }

      expect_status(200)
      expect(events.first['id']).to eq(event_user_monitoring.id)

      as(admin) { json_get index_path, monitored_event: { order: 'oldest' } }

      expect_status(200)
      expect(events.first['id']).to eq(event_user_high_access.id)
    end

    it 'orders by longest and shortest durations' do
      as(admin) { json_get index_path, monitored_event: { order: 'longest' } }

      expect_status(200)
      expect(events.first['id']).to eq(event_user_confirmed.id)
      expect(events[1]['id']).to eq(event_user_closed.id)

      durations = events.map { |row| row['duration'].to_f }
      expect(durations.first).to be_within(2).of(120)
      expect(durations[1]).to be_within(2).of(60)
      expect(durations.drop(2)).to all(be_within(2).of(10))

      as(admin) { json_get index_path, monitored_event: { order: 'shortest' } }

      expect_status(200)
      durations = events.map { |row| row['duration'].to_f }
      expect(durations.first).to be_within(2).of(10)
      expect(events.last['id']).to eq(event_user_confirmed.id)
    end

    it 'paginates by duration using from_duration' do
      as(admin) { json_get index_path, monitored_event: { order: 'longest', from_duration: 60 } }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).not_to include(event_user_confirmed.id, event_user_closed.id)
      expect(events.map { |row| row['duration'].to_f }).to all(be < 60)

      as(admin) { json_get index_path, monitored_event: { order: 'shortest', from_duration: 60 } }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(event_user_confirmed.id)
    end

    it 'returns meta count for user visibility' do
      as(user) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(2)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(event_user_confirmed.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows own confirmed event for user' do
      as(user) { json_get show_path(event_user_confirmed.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(event_obj['id']).to eq(event_user_confirmed.id)
      expect(event_obj['monitor']).to eq('spec_a')
      expect(event_obj['state']).to eq('confirmed')
      expect(rid(event_obj['user'])).to eq(user.id)
      expect(event_obj['label']).to eq('Spec Monitor A')
      expect(event_obj['issue']).to eq('Spec Issue A')
      expect(event_obj['duration'].to_f).to be_within(2).of(120)
    end

    it 'rejects user access to other or disallowed events' do
      as(user) { json_get show_path(event_other_confirmed.id) }

      expect_status(404)
      expect(json['status']).to be(false)

      as(user) { json_get show_path(event_user_monitoring.id) }

      expect_status(404)
      expect(json['status']).to be(false)

      as(user) { json_get show_path(event_user_high_access.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show other user events within access level' do
      as(admin) { json_get show_path(event_other_confirmed.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Acknowledge' do
    it 'rejects unauthenticated access' do
      json_post ack_path(event_user_confirmed.id), monitored_event: { until: (now + 1.day).iso8601 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to acknowledge confirmed event' do
      until_time = now + 1.day
      as(user) { json_post ack_path(event_user_confirmed.id), monitored_event: { until: until_time.iso8601 } }

      expect_status(200)
      expect(json['status']).to be(true)

      event_user_confirmed.reload
      expect(event_user_confirmed.state).to eq('acknowledged')
      expect(event_user_confirmed.saved_until.to_i).to be_within(2).of(until_time.to_i)
    end

    it 'returns error for closed event' do
      as(user) { json_post ack_path(event_user_closed.id), monitored_event: { until: (now + 2.days).iso8601 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('cannot be acknowledged')

      event_user_closed.reload
      expect(event_user_closed.state).to eq('closed')
    end

    it 'does not allow user to acknowledge other user event' do
      as(user) { json_post ack_path(event_other_confirmed.id), monitored_event: { until: (now + 1.day).iso8601 } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to acknowledge other user event' do
      until_time = now + 3.days
      as(admin) { json_post ack_path(event_other_confirmed.id), monitored_event: { until: until_time.iso8601 } }

      expect_status(200)
      expect(json['status']).to be(true)

      event_other_confirmed.reload
      expect(event_other_confirmed.state).to eq('acknowledged')
      expect(event_other_confirmed.saved_until.to_i).to be_within(2).of(until_time.to_i)
    end
  end

  describe 'Ignore' do
    it 'rejects unauthenticated access' do
      json_post ignore_path(event_user_confirmed.id), monitored_event: { until: (now + 1.day).iso8601 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to ignore confirmed event' do
      until_time = now + 1.day
      as(user) { json_post ignore_path(event_user_confirmed.id), monitored_event: { until: until_time.iso8601 } }

      expect_status(200)
      expect(json['status']).to be(true)

      event_user_confirmed.reload
      expect(event_user_confirmed.state).to eq('ignored')
      expect(event_user_confirmed.saved_until.to_i).to be_within(2).of(until_time.to_i)
    end

    it 'returns error for closed event' do
      as(user) { json_post ignore_path(event_user_closed.id), monitored_event: { until: (now + 2.days).iso8601 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('cannot be ignored')

      event_user_closed.reload
      expect(event_user_closed.state).to eq('closed')
    end

    it 'does not allow user to ignore other user event' do
      as(user) { json_post ignore_path(event_other_confirmed.id), monitored_event: { until: (now + 1.day).iso8601 } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to ignore other user event' do
      until_time = now + 3.days
      as(admin) { json_post ignore_path(event_other_confirmed.id), monitored_event: { until: until_time.iso8601 } }

      expect_status(200)
      expect(json['status']).to be(true)

      event_other_confirmed.reload
      expect(event_other_confirmed.state).to eq('ignored')
      expect(event_other_confirmed.saved_until.to_i).to be_within(2).of(until_time.to_i)
    end
  end

  describe 'Logs Index' do
    it 'rejects unauthenticated access' do
      json_get logs_path(event_user_confirmed.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists logs for own event in oldest order by default' do
      as(user) { json_get logs_path(event_user_confirmed.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      values = logs.map { |row| row['value'] }
      expect(values).to eq(%w[ok fail ok2])
    end

    it 'orders logs by latest' do
      as(user) { json_get logs_path(event_user_confirmed.id), log: { order: 'latest' } }

      expect_status(200)
      expect(json['status']).to be(true)

      values = logs.map { |row| row['value'] }
      expect(values).to eq(%w[ok2 fail ok])
    end

    it 'filters logs by passed status' do
      as(user) { json_get logs_path(event_user_confirmed.id), log: { passed: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(logs.map { |row| row['id'] }).to contain_exactly(log_ok.id, log_ok_again.id)

      as(user) { json_get logs_path(event_user_confirmed.id), log: { passed: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(logs.map { |row| row['id'] }).to contain_exactly(log_fail.id)
    end

    it 'returns empty list for other user events' do
      as(user) { json_get logs_path(event_other_confirmed.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(logs).to eq([])
    end

    it 'returns meta count' do
      as(user) { json_get logs_path(event_user_confirmed.id), _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(3)
    end
  end

  describe 'Logs Show' do
    it 'rejects unauthenticated access' do
      json_get log_path(event_user_confirmed.id, log_ok.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows own log for user' do
      as(user) { json_get log_path(event_user_confirmed.id, log_ok.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(log_obj['id']).to eq(log_ok.id)
      expect(log_obj['passed']).to be(true)
      expect(log_obj['value']).to eq('ok')
    end

    it 'does not allow user to show other user log' do
      as(user) { json_get log_path(event_other_confirmed.id, log_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any log' do
      as(admin) { json_get log_path(event_other_confirmed.id, log_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end
end
