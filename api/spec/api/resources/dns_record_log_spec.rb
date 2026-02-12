# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::DnsRecordLog' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.other_user
    seed
  end

  def index_path
    vpath('/dns_record_logs')
  end

  def show_path(id)
    vpath("/dns_record_logs/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def logs
    json.dig('response', 'dns_record_logs')
  end

  def log_obj
    json.dig('response', 'dns_record_log') || json['response']
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

  def create_chain(user:, session:, name:)
    TransactionChain.create!(
      name: name,
      type: 'TransactionChain',
      state: :queued,
      size: 1,
      progress: 0,
      user: user,
      user_session: session,
      concern_type: :chain_affect
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

  def create_log!(dns_zone:, user:, chain:, change_type:, name:, record_type:, created_at:)
    DnsRecordLog.create!(
      dns_zone: dns_zone,
      dns_zone_name: dns_zone.name,
      user: user,
      transaction_chain: chain,
      change_type: change_type,
      name: name,
      record_type: record_type,
      attr_changes: { 'content' => %w[old new] },
      created_at: created_at,
      updated_at: created_at
    )
  end

  let(:seed) do
    base_time = Time.utc(2040, 1, 1, 12, 0, 0)
    user = SpecSeed.user
    other_user = SpecSeed.other_user
    support = SpecSeed.support
    admin = SpecSeed.admin

    session_user = create_session(
      user: user,
      ip: '192.0.2.10',
      user_agent: 'SpecUA/DNSLog1',
      label: 'Spec DNS Log User'
    )
    session_other_user = create_session(
      user: other_user,
      ip: '192.0.2.20',
      user_agent: 'SpecUA/DNSLog2',
      label: 'Spec DNS Log Other'
    )
    session_support = create_session(
      user: support,
      ip: '192.0.2.30',
      user_agent: 'SpecUA/DNSLog3',
      label: 'Spec DNS Log Support'
    )
    session_admin = create_session(
      user: admin,
      ip: '192.0.2.40',
      user_agent: 'SpecUA/DNSLog4',
      label: 'Spec DNS Log Admin'
    )

    chain_user = create_chain(user: user, session: session_user, name: 'spec_dns_log_user')
    chain_other_user = create_chain(user: other_user, session: session_other_user, name: 'spec_dns_log_other')
    chain_support = create_chain(user: support, session: session_support, name: 'spec_dns_log_support')
    chain_admin = create_chain(user: admin, session: session_admin, name: 'spec_dns_log_admin')

    zone_user = create_zone!(user: user, name: "spec-user-#{SecureRandom.hex(3)}.example.test.")
    zone_other = create_zone!(user: other_user, name: "spec-other-#{SecureRandom.hex(3)}.example.test.")
    zone_support = create_zone!(user: support, name: "spec-support-#{SecureRandom.hex(3)}.example.test.")

    log_user_a = create_log!(
      dns_zone: zone_user,
      user: user,
      chain: chain_user,
      change_type: :create_record,
      name: 'www',
      record_type: 'A',
      created_at: base_time + 60
    )
    log_admin_in_user_zone = create_log!(
      dns_zone: zone_user,
      user: admin,
      chain: chain_admin,
      change_type: :delete_record,
      name: 'admin',
      record_type: 'A',
      created_at: base_time + 120
    )
    log_user_b = create_log!(
      dns_zone: zone_user,
      user: user,
      chain: chain_user,
      change_type: :update_record,
      name: 'mail',
      record_type: 'MX',
      created_at: base_time + 180
    )
    log_support = create_log!(
      dns_zone: zone_support,
      user: support,
      chain: chain_support,
      change_type: :create_record,
      name: 'support',
      record_type: 'A',
      created_at: base_time + 240
    )
    log_other = create_log!(
      dns_zone: zone_other,
      user: other_user,
      chain: chain_other_user,
      change_type: :create_record,
      name: 'www',
      record_type: 'AAAA',
      created_at: base_time + 300
    )

    {
      zone_user: zone_user,
      zone_other: zone_other,
      zone_support: zone_support,
      log_user_a: log_user_a,
      log_user_b: log_user_b,
      log_admin_in_user_zone: log_admin_in_user_zone,
      log_other: log_other,
      log_support: log_support
    }
  end

  describe 'API description' do
    it 'includes dns_record_log scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('dns_record_log#index', 'dns_record_log#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to list only their logs in their zones' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(logs).to be_an(Array)

      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(seed[:log_user_a].id, seed[:log_user_b].id)

      row = logs.find { |item| item['id'] == seed[:log_user_a].id }
      expect(row).not_to have_key('user')
    end

    it 'allows support to list only their logs in their zones' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(seed[:log_support].id)

      row = logs.find { |item| item['id'] == seed[:log_support].id }
      expect(row).not_to have_key('user')
    end

    it 'allows admins to list all logs with user details' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(
        seed[:log_user_a].id,
        seed[:log_user_b].id,
        seed[:log_admin_in_user_zone].id,
        seed[:log_other].id,
        seed[:log_support].id
      )

      row = logs.find { |item| item['id'] == seed[:log_user_a].id }
      expect(row['user']).to be_a(Hash)
    end

    it 'orders logs by created_at desc for admins' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(logs.first['id']).to eq(seed[:log_other].id)
    end

    it 'filters by user for admins' do
      as(SpecSeed.admin) { json_get index_path, dns_record_log: { user: SpecSeed.user.id } }

      expect_status(200)
      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(seed[:log_user_a].id, seed[:log_user_b].id)
    end

    it 'filters by dns_zone for admins' do
      as(SpecSeed.admin) { json_get index_path, dns_record_log: { dns_zone: seed[:zone_user].id } }

      expect_status(200)
      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(
        seed[:log_user_a].id,
        seed[:log_user_b].id,
        seed[:log_admin_in_user_zone].id
      )
    end

    it 'filters by dns_zone_name for admins' do
      as(SpecSeed.admin) { json_get index_path, dns_record_log: { dns_zone_name: seed[:zone_user].name } }

      expect_status(200)
      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(
        seed[:log_user_a].id,
        seed[:log_user_b].id,
        seed[:log_admin_in_user_zone].id
      )
    end

    it 'filters by change_type for admins' do
      as(SpecSeed.admin) { json_get index_path, dns_record_log: { change_type: 'update_record' } }

      expect_status(200)
      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(seed[:log_user_b].id)
    end

    it 'filters by name for admins' do
      as(SpecSeed.admin) { json_get index_path, dns_record_log: { name: 'www' } }

      expect_status(200)
      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(seed[:log_user_a].id, seed[:log_other].id)
    end

    it 'filters by type for admins' do
      as(SpecSeed.admin) { json_get index_path, dns_record_log: { type: 'MX' } }

      expect_status(200)
      ids = logs.map { |row| rid(row) }
      expect(ids).to contain_exactly(seed[:log_user_b].id)
    end

    it 'rejects or ignores user filter for non-admins' do
      as(SpecSeed.user) { json_get index_path, dns_record_log: { user: SpecSeed.other_user.id } }

      if json['status'] == false
        errors = json.dig('response', 'errors') || json['errors'] || {}
        if errors.respond_to?(:keys) && errors.any?
          expect(errors.keys.map(&:to_s)).to include('user')
        end
      else
        expect_status(200)
      end

      ids = Array(logs).map { |row| row['id'] }
      expect(ids).not_to include(seed[:log_other].id, seed[:log_admin_in_user_zone].id)
    end

    it 'rejects or ignores dns_zone_name filter for non-admins' do
      as(SpecSeed.user) { json_get index_path, dns_record_log: { dns_zone_name: seed[:zone_user].name } }

      expect(last_response.status).to be < 500

      ids = Array(logs).map { |row| row['id'] }
      expect(ids).not_to include(seed[:log_other].id, seed[:log_admin_in_user_zone].id)
    end

    it 'supports pagination and meta count for admins' do
      as(SpecSeed.admin) { json_get index_path, dns_record_log: { limit: 2 } }

      expect_status(200)
      expect(logs.length).to eq(2)

      boundary = DnsRecordLog.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, dns_record_log: { from_id: boundary } }

      expect_status(200)
      ids = logs.map { |row| row['id'] }
      expect(ids).to all(be > boundary)

      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(DnsRecordLog.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(seed[:log_user_a].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their log without user object' do
      as(SpecSeed.user) { json_get show_path(seed[:log_user_a].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(log_obj['id']).to eq(seed[:log_user_a].id)
      expect(log_obj).not_to have_key('user')
    end

    it 'prevents users from showing admin logs in their zone' do
      as(SpecSeed.user) { json_get show_path(seed[:log_admin_in_user_zone].id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'prevents users from showing other user logs' do
      as(SpecSeed.user) { json_get show_path(seed[:log_other].id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'allows support to show their log without user object' do
      as(SpecSeed.support) { json_get show_path(seed[:log_support].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(log_obj['id']).to eq(seed[:log_support].id)
      expect(log_obj).not_to have_key('user')
    end

    it 'allows admins to show any log with user details' do
      as(SpecSeed.admin) { json_get show_path(seed[:log_other].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(log_obj['id']).to eq(seed[:log_other].id)
      expect(log_obj['user']).to be_a(Hash)
      expect(log_obj['raw_user_id']).to eq(seed[:log_other].user_id)
    end

    it 'returns 404 for unknown log id' do
      missing = DnsRecordLog.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end
end
