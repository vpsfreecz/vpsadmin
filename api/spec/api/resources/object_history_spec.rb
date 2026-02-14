# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::ObjectHistory' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.support
    SpecSeed.admin
    seed
  end

  def index_path
    vpath('/object_histories')
  end

  def show_path(id)
    vpath("/object_histories/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def events
    json.dig('response', 'object_histories')
  end

  def event_obj
    json.dig('response', 'object_history') || json['response']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def create_session(user:, ip:, user_agent:, label:)
    UserSession.create!(
      user: user,
      auth_type: 'basic',
      api_ip_addr: ip,
      client_ip_addr: ip,
      user_agent: UserAgent.find_or_create!(user_agent),
      client_version: user_agent,
      scope: ['all'],
      label: label,
      token_lifetime: :fixed,
      token_interval: 3600
    )
  end

  def create_zone!(user:, name:)
    DnsZone.create!(
      user: user,
      name: name,
      email: 'hostmaster@example.test',
      default_ttl: 3600,
      zone_role: :forward_role,
      zone_source: :internal_source,
      enabled: true
    )
  end

  def create_event!(user:, session:, tracked_object:, event_type:, event_data:, created_at:)
    ObjectHistory.create!(
      user: user,
      user_session: session,
      tracked_object: tracked_object,
      event_type: event_type,
      event_data: event_data,
      created_at: created_at
    )
  end

  let(:seed) do
    base_time = Time.utc(2040, 1, 1, 12, 0, 0)
    user = SpecSeed.user
    other_user = SpecSeed.other_user
    support = SpecSeed.support
    admin = SpecSeed.admin

    session_user_a = create_session(
      user: user,
      ip: '192.0.2.10',
      user_agent: 'SpecUA/OH1',
      label: 'Spec ObjectHistory User A'
    )
    session_user_b = create_session(
      user: user,
      ip: '192.0.2.11',
      user_agent: 'SpecUA/OH2',
      label: 'Spec ObjectHistory User B'
    )
    session_other = create_session(
      user: other_user,
      ip: '192.0.2.20',
      user_agent: 'SpecUA/OH3',
      label: 'Spec ObjectHistory Other'
    )
    session_support = create_session(
      user: support,
      ip: '192.0.2.30',
      user_agent: 'SpecUA/OH4',
      label: 'Spec ObjectHistory Support'
    )
    session_admin = create_session(
      user: admin,
      ip: '192.0.2.40',
      user_agent: 'SpecUA/OH5',
      label: 'Spec ObjectHistory Admin'
    )

    zone_user = create_zone!(user: user, name: "spec-oh-#{SecureRandom.hex(3)}.example.test.")

    ev_user_a = create_event!(
      user: user,
      session: session_user_a,
      tracked_object: user,
      event_type: 'update',
      event_data: { 'field' => 'full_name', 'from' => 'A', 'to' => 'B' },
      created_at: base_time + 60
    )
    ev_user_b = create_event!(
      user: user,
      session: session_user_b,
      tracked_object: zone_user,
      event_type: 'dns_update',
      event_data: { 'zone' => zone_user.name },
      created_at: base_time + 120
    )
    ev_other = create_event!(
      user: other_user,
      session: session_other,
      tracked_object: other_user,
      event_type: 'create',
      event_data: { 'x' => 1 },
      created_at: base_time + 180
    )
    ev_admin = create_event!(
      user: admin,
      session: session_admin,
      tracked_object: zone_user,
      event_type: 'admin_action',
      event_data: { 'action' => 'touch' },
      created_at: base_time + 240
    )
    ev_support = create_event!(
      user: support,
      session: session_support,
      tracked_object: support,
      event_type: 'support_action',
      event_data: { 'note' => 'ok' },
      created_at: base_time + 300
    )

    {
      zone_user: zone_user,
      session_user_a: session_user_a,
      session_user_b: session_user_b,
      session_other: session_other,
      session_support: session_support,
      session_admin: session_admin,
      ev_user_a: ev_user_a,
      ev_user_b: ev_user_b,
      ev_other: ev_other,
      ev_admin: ev_admin,
      ev_support: ev_support
    }
  end

  describe 'API description' do
    it 'includes object_history scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('object_history#index', 'object_history#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to list only their events' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(events).to be_an(Array)

      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:ev_user_a].id, seed[:ev_user_b].id)

      row = events.find { |item| item['id'] == seed[:ev_user_a].id }
      expect(row).to include('id', 'event_type', 'event_data', 'created_at', 'object', 'object_id', 'user', 'user_session')
      expect(row['event_type']).to eq('update')
      expect(row['event_data']).to be_a(Hash)
      expect(row['event_data']).to include('field' => 'full_name', 'from' => 'A', 'to' => 'B')
      expect(row['object']).to eq('User')
      expect(row['object_id']).to eq(SpecSeed.user.id)
      expect(rid(row['user'])).to eq(SpecSeed.user.id)
      expect([seed[:session_user_a].id, seed[:session_user_b].id]).to include(rid(row['user_session']))
    end

    it 'allows support users to list only their events' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:ev_support].id)
    end

    it 'allows admins to list all events' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(
        seed[:ev_user_a].id,
        seed[:ev_user_b].id,
        seed[:ev_other].id,
        seed[:ev_admin].id,
        seed[:ev_support].id
      )

      row = events.find { |item| item['id'] == seed[:ev_user_a].id }
      expect(rid(row['user'])).to eq(SpecSeed.user.id)
    end

    it 'ignores user filter for non-admin users' do
      as(SpecSeed.user) { json_get index_path, object_history: { user: SpecSeed.other_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:ev_user_a].id, seed[:ev_user_b].id)
    end

    it 'allows admins to filter by user' do
      as(SpecSeed.admin) { json_get index_path, object_history: { user: SpecSeed.user.id } }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:ev_user_a].id, seed[:ev_user_b].id)
    end

    it 'filters by user_session' do
      as(SpecSeed.user) { json_get index_path, object_history: { user_session: seed[:session_user_a].id } }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:ev_user_a].id)
    end

    it 'filters by object type' do
      as(SpecSeed.admin) { json_get index_path, object_history: { object: 'User' } }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:ev_user_a].id, seed[:ev_other].id, seed[:ev_support].id)
    end

    it 'filters by object id' do
      as(SpecSeed.admin) do
        json_get index_path, object_history: { object: 'DnsZone', object_id: seed[:zone_user].id }
      end

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:ev_user_b].id, seed[:ev_admin].id)
    end

    it 'filters by event_type' do
      as(SpecSeed.admin) { json_get index_path, object_history: { event_type: 'dns_update' } }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:ev_user_b].id)
    end

    it 'orders by created_at and id ascending' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expected = [
        seed[:ev_user_a],
        seed[:ev_user_b],
        seed[:ev_other],
        seed[:ev_admin],
        seed[:ev_support]
      ].sort_by { |event| [event.created_at, event.id] }
      expect(ids).to eq(expected.map(&:id))
    end

    it 'supports pagination and meta count for admins' do
      as(SpecSeed.admin) { json_get index_path, object_history: { limit: 2 } }

      expect_status(200)
      expect(events.length).to eq(2)

      boundary = events.first['id']
      as(SpecSeed.admin) { json_get index_path, object_history: { from_id: boundary } }

      expect_status(200)
      ids = events.map { |row| row['id'] }
      expect(ids).to all(be > boundary)

      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(ObjectHistory.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(seed[:ev_user_a].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their event' do
      as(SpecSeed.user) { json_get show_path(seed[:ev_user_a].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(event_obj['id']).to eq(seed[:ev_user_a].id)
      expect(rid(event_obj['user'])).to eq(SpecSeed.user.id)
      expect(event_obj['event_type']).to eq('update')
      expect(event_obj['event_data']).to include('field' => 'full_name', 'from' => 'A', 'to' => 'B')
      expect(event_obj['object']).to eq('User')
      expect(event_obj['object_id']).to eq(SpecSeed.user.id)
    end

    it 'returns 404 for other users events' do
      as(SpecSeed.user) { json_get show_path(seed[:ev_other].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any event' do
      as(SpecSeed.admin) { json_get show_path(seed[:ev_other].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rid(event_obj['user'])).to eq(SpecSeed.other_user.id)
    end

    it 'returns 404 for unknown event id' do
      missing = ObjectHistory.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
