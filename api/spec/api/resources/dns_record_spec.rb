# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::DnsRecord' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.other_user

    ensure_ddns_url!('ipv4_ddns_url', 'https://ddns.example.test')
    ensure_ddns_url!('ipv6_ddns_url', 'https://ddns6.example.test')
    seed
  end

  def index_path
    vpath('/dns_records')
  end

  def show_path(id)
    vpath("/dns_records/#{id}")
  end

  def dynamic_update_path(token)
    vpath("/dns_records/dynamic_update/#{token}")
  end

  def json_get(path, params = nil, env = {})
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }.merge(env)
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def records
    json.dig('response', 'dns_records') || []
  end

  def record_obj
    json.dig('response', 'dns_record') || json['dns_record'] || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def ensure_ddns_url!(name, value)
    cfg = SysConfig.find_or_initialize_by(category: 'core', name: name)
    cfg.data_type ||= 'String'
    cfg.value = value
    cfg.save! if cfg.changed?
  end

  def create_zone!(name:, user: nil, role: :forward_role, source: :internal_source, enabled: true,
                   label: '', default_ttl: 3600, email: 'dns@example.test',
                   reverse_network_address: nil, reverse_network_prefix: nil)
    DnsZone.create!(
      name: name,
      user: user,
      zone_role: role,
      zone_source: source,
      enabled: enabled,
      label: label,
      default_ttl: default_ttl,
      email: email,
      reverse_network_address: reverse_network_address,
      reverse_network_prefix: reverse_network_prefix
    )
  end

  def create_record!(zone:, name:, record_type:, content:, priority: nil, user: nil)
    DnsRecord.create!(
      dns_zone: zone,
      name: name,
      record_type: record_type,
      content: content,
      priority: priority,
      user: user
    )
  end

  let(:seed) do
    system_zone = create_zone!(
      name: 'spec-system.example.test.',
      role: :forward_role,
      source: :internal_source,
      email: 'admin@example.test'
    )
    user_zone = create_zone!(
      name: 'spec-user.example.test.',
      user: SpecSeed.user,
      role: :forward_role,
      source: :external_source,
      email: 'user@example.test'
    )
    support_zone = create_zone!(
      name: 'spec-support.example.test.',
      user: SpecSeed.support,
      role: :forward_role,
      source: :external_source,
      email: 'support@example.test'
    )

    dns_server = DnsServer.create!(
      node: SpecSeed.node,
      name: 'spec-dns-1',
      ipv4_addr: '192.0.2.53'
    )
    dns_server_zone = DnsServerZone.create!(
      dns_zone: system_zone,
      dns_server: dns_server,
      zone_type: :primary_type
    )

    record_system_a = create_record!(
      zone: system_zone,
      name: 'www',
      record_type: 'A',
      content: '192.0.2.123'
    )
    record_system_user = create_record!(
      zone: system_zone,
      name: 'user',
      record_type: 'A',
      content: '192.0.2.126',
      user: SpecSeed.user
    )
    record_user_a = create_record!(
      zone: user_zone,
      name: 'www',
      record_type: 'A',
      content: '192.0.2.124'
    )
    record_user_mx = create_record!(
      zone: user_zone,
      name: '@',
      record_type: 'MX',
      content: 'mail.user.example.test.',
      priority: 10
    )
    record_support_a = create_record!(
      zone: support_zone,
      name: 'www',
      record_type: 'A',
      content: '192.0.2.125'
    )

    {
      system_zone: system_zone,
      user_zone: user_zone,
      support_zone: support_zone,
      dns_server: dns_server,
      dns_server_zone: dns_server_zone,
      record_system_a: record_system_a,
      record_system_user: record_system_user,
      record_user_a: record_user_a,
      record_user_mx: record_user_mx,
      record_support_a: record_support_a
    }
  end

  describe 'API description' do
    it 'includes dns record endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'dns_record#index',
        'dns_record#show',
        'dns_record#create',
        'dns_record#update',
        'dns_record#delete',
        'dns_record#dynamic_update'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists records for user-owned zones' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(records).to be_an(Array)

      ids = records.map { |row| row['id'] }
      expect(ids).to include(seed[:record_user_a].id, seed[:record_user_mx].id)
      expect(ids).not_to include(seed[:record_system_a].id, seed[:record_system_user].id, seed[:record_support_a].id)

      row = records.find { |item| item['id'] == seed[:record_user_a].id }
      expect(row).to include('id', 'name', 'type', 'content')
      expect(row).not_to have_key('user')
      expect(rid(row['dns_zone'])).to eq(seed[:user_zone].id)
    end

    it 'lists records for support-owned zones' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = records.map { |row| row['id'] }
      expect(ids).to include(seed[:record_support_a].id)
      expect(ids).not_to include(seed[:record_system_a].id, seed[:record_system_user].id, seed[:record_user_a].id)
    end

    it 'allows admins to list all records with user field' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = records.map { |row| row['id'] }
      expect(ids).to include(seed[:record_system_a].id, seed[:record_system_user].id, seed[:record_user_a].id, seed[:record_support_a].id)

      row = records.find { |item| item['id'] == seed[:record_system_user].id }
      expect(row).to have_key('user')
      expect(rid(row['user'])).to eq(SpecSeed.user.id)
    end

    it 'filters by dns_zone' do
      as(SpecSeed.admin) { json_get index_path, dns_record: { dns_zone: seed[:user_zone].id } }

      expect_status(200)
      ids = records.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:record_user_a].id, seed[:record_user_mx].id)
    end

    it 'filters by user' do
      as(SpecSeed.admin) { json_get index_path, dns_record: { user: SpecSeed.user.id } }

      expect_status(200)
      ids = records.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:record_system_user].id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(seed[:record_system_a].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their record' do
      as(SpecSeed.user) { json_get show_path(seed[:record_user_a].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(record_obj['id']).to eq(seed[:record_user_a].id)
      expect(record_obj['name']).to eq(seed[:record_user_a].name)
      expect(record_obj['type']).to eq(seed[:record_user_a].record_type)
      expect(record_obj['content']).to eq(seed[:record_user_a].content)
      expect(record_obj).not_to have_key('user')
    end

    it 'denies users from other zones' do
      as(SpecSeed.user) { json_get show_path(seed[:record_system_a].id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any record with user field' do
      as(SpecSeed.admin) { json_get show_path(seed[:record_system_user].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(record_obj['id']).to eq(seed[:record_system_user].id)
      expect(record_obj).to have_key('user')
      expect(rid(record_obj['user'])).to eq(SpecSeed.user.id)
    end

    it 'returns 404 for unknown record' do
      missing = DnsRecord.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:user_payload) do
      {
        dns_zone: seed[:user_zone].id,
        name: 'api',
        type: 'A',
        content: '192.0.2.200',
        ttl: 3600
      }
    end

    let(:admin_payload) do
      {
        dns_zone: seed[:system_zone].id,
        name: 'admin',
        type: 'A',
        content: '192.0.2.201',
        ttl: 3600
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, dns_record: user_payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects users creating records outside their zone' do
      as(SpecSeed.user) { json_post index_path, dns_record: admin_payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('access to the zone denied')
    end

    it 'allows users to create records in their zone' do
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.user) { json_post index_path, dns_record: user_payload }
      end.to change(DnsRecord, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(record_obj).to be_a(Hash)
      expect(record_obj['name']).to eq('api')
      expect(record_obj['type']).to eq('A')
      expect(record_obj['content']).to eq('192.0.2.200')
    end

    it 'allows admins to create records with a transaction chain' do
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.admin) { json_post index_path, dns_record: admin_payload }
      end.to change(DnsRecord, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(record_obj['name']).to eq('admin')
      expect(record_obj['type']).to eq('A')
      expect(action_state_id.to_i).to be > 0
    end

    it 'returns validation errors for missing name' do
      as(SpecSeed.admin) { json_post index_path, dns_record: user_payload.except(:name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('name')
    end

    it 'returns validation errors for invalid type' do
      as(SpecSeed.admin) do
        json_post index_path, dns_record: user_payload.merge(type: 'INVALID')
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('type')
    end

    it 'returns validation errors for invalid content' do
      as(SpecSeed.admin) do
        json_post index_path, dns_record: user_payload.merge(content: 'not-an-ip')
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('content')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(seed[:record_user_a].id), dns_record: { content: '192.0.2.210' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for users updating other zones' do
      as(SpecSeed.user) { json_put show_path(seed[:record_system_a].id), dns_record: { content: '192.0.2.211' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows users to update their record' do
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_put show_path(seed[:record_user_a].id), dns_record: { content: '192.0.2.212' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(record_obj).to be_a(Hash)
      expect(record_obj['content']).to eq('192.0.2.212')
      expect(seed[:record_user_a].reload.content).to eq('192.0.2.212')
    end

    it 'allows admins to update records with a transaction chain' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) do
        json_put show_path(seed[:record_system_a].id), dns_record: { content: '192.0.2.213', ttl: 7200 }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(record_obj['content']).to eq('192.0.2.213')
      expect(record_obj['ttl']).to eq(7200)
      expect(action_state_id.to_i).to be > 0
    end

    it 'returns validation errors for invalid content' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) do
        json_put show_path(seed[:record_system_a].id), dns_record: { content: 'invalid-ip' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('content')
    end

    it 'returns validation errors for invalid ttl' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) do
        json_put show_path(seed[:record_system_a].id), dns_record: { ttl: 10 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('ttl')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(seed[:record_user_a].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for users deleting other zones' do
      as(SpecSeed.user) { json_delete show_path(seed[:record_system_a].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows users to delete their record' do
      ensure_signer_unlocked!

      record = create_record!(
        zone: seed[:user_zone],
        name: 'delete-me',
        record_type: 'A',
        content: '192.0.2.220'
      )

      as(SpecSeed.user) { json_delete show_path(record.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(DnsRecord.existing.where(id: record.id)).to be_empty
    end

    it 'allows admins to delete records with a transaction chain' do
      ensure_signer_unlocked!

      record = create_record!(
        zone: seed[:system_zone],
        name: 'admin-delete',
        record_type: 'A',
        content: '192.0.2.221'
      )

      as(SpecSeed.admin) { json_delete show_path(record.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(DnsRecord.existing.where(id: record.id)).to be_empty
    end

    it 'returns 404 for unknown record' do
      missing = DnsRecord.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'DynamicUpdate' do
    let!(:dynamic_record) do
      record = create_record!(
        zone: seed[:system_zone],
        name: 'dyn',
        record_type: 'A',
        content: '192.0.2.150'
      )
      record.update!(update_token: Token.get!(owner: record))
      record
    end

    it 'updates content using the client address' do
      ensure_signer_unlocked!

      json_get dynamic_update_path(dynamic_record.update_token.token), nil, {
        'HTTP_X_REAL_IP' => '192.0.2.200'
      }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(record_obj['content']).to eq('192.0.2.200')
      expect(action_state_id.to_i).to be > 0
      expect(dynamic_record.reload.content).to eq('192.0.2.200')
    end

    it 'returns 404 for unknown token' do
      json_get dynamic_update_path('missing-token')

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end
end
