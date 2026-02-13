# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::DnsServer' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.support
    SpecSeed.user
    SpecSeed.node
    SpecSeed.other_node
  end

  def index_path
    vpath('/dns_servers')
  end

  def show_path(id)
    vpath("/dns_servers/#{id}")
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

  def json_put(path, payload)
    put path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def servers
    json.dig('response', 'dns_servers') || []
  end

  def server_obj
    json.dig('response', 'dns_server') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_input_params(resource_name, action_name)
    header 'Accept', 'application/json'
    options vpath('/')
    expect(last_response.status).to eq(200)

    data = json
    data = data['response'] if data.is_a?(Hash) && data['response'].is_a?(Hash)

    resources = data['resources'] || {}
    action = resources.dig(resource_name.to_s, 'actions', action_name.to_s) || {}
    action.dig('input', 'parameters') || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def resource_id(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def random_ipv4
    "192.0.2.#{200 + SecureRandom.random_number(40)}"
  end

  def random_ipv6
    "2001:db8::#{SecureRandom.hex(2)}"
  end

  def create_server!(name_prefix:, enable_user_dns_zones:, node: SpecSeed.node, hidden: false,
                     ipv4: random_ipv4, ipv6: nil, user_dns_zone_type: :primary_type)
    suffix = SecureRandom.hex(4)

    DnsServer.create!(
      node: node,
      name: "#{name_prefix}-#{suffix}.example.test",
      ipv4_addr: ipv4,
      ipv6_addr: ipv6,
      hidden: hidden,
      enable_user_dns_zones: enable_user_dns_zones,
      user_dns_zone_type: user_dns_zone_type
    )
  end

  def create_zone!(name_prefix:, user: SpecSeed.admin, source: :internal_source)
    suffix = SecureRandom.hex(4)

    DnsZone.create!(
      user: user,
      name: "#{name_prefix}-#{suffix}.example.test.",
      label: '',
      zone_role: :forward_role,
      zone_source: source,
      enabled: true,
      default_ttl: 3600,
      email: 'admin@example.test'
    )
  end

  def attach_zone!(server:, zone:)
    DnsServerZone.create!(
      dns_server: server,
      dns_zone: zone
    )
  end

  let!(:user_dns_server) do
    create_server!(
      name_prefix: 'spec-user-dns',
      enable_user_dns_zones: true,
      hidden: false
    )
  end

  let!(:internal_dns_server) do
    create_server!(
      name_prefix: 'spec-internal-dns',
      enable_user_dns_zones: false,
      hidden: true,
      node: SpecSeed.other_node
    )
  end

  describe 'API description' do
    it 'includes dns_server endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'dns_server#index',
        'dns_server#show',
        'dns_server#create',
        'dns_server#update',
        'dns_server#delete'
      )
    end

    it 'documents dns_server inputs' do
      create_params = action_input_params('dns_server', 'create')
      update_params = action_input_params('dns_server', 'update')

      expect(create_params.keys).to include(
        'node',
        'name',
        'ipv4_addr',
        'ipv6_addr',
        'hidden',
        'enable_user_dns_zones',
        'user_dns_zone_type'
      )
      expect(update_params.keys).to include(
        'node',
        'name',
        'ipv4_addr',
        'ipv6_addr',
        'hidden',
        'enable_user_dns_zones',
        'user_dns_zone_type'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns only user-enabled servers for users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(servers).to be_an(Array)

      ids = servers.map { |row| row['id'] }
      expect(ids).to include(user_dns_server.id)
      expect(ids).not_to include(internal_dns_server.id)

      row = servers.find { |item| item['id'] == user_dns_server.id }
      expect(row).to include(
        'id',
        'node',
        'name',
        'ipv4_addr',
        'ipv6_addr',
        'hidden',
        'enable_user_dns_zones',
        'user_dns_zone_type',
        'created_at',
        'updated_at'
      )
      expect(resource_id(row['node'])).to eq(user_dns_server.node_id)
    end

    it 'returns only user-enabled servers for support' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(servers).to be_an(Array)

      ids = servers.map { |row| row['id'] }
      expect(ids).to include(user_dns_server.id)
      expect(ids).not_to include(internal_dns_server.id)
    end

    it 'returns all servers for admins' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = servers.map { |row| row['id'] }
      expect(ids).to include(user_dns_server.id, internal_dns_server.id)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, dns_server: { limit: 1 } }

      expect_status(200)
      expect(servers.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = DnsServer.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, dns_server: { from_id: boundary } }

      expect_status(200)
      ids = servers.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(DnsServer.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_dns_server.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show user-enabled servers' do
      as(SpecSeed.user) { json_get show_path(user_dns_server.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(server_obj).to include(
        'id',
        'node',
        'name',
        'ipv4_addr',
        'ipv6_addr',
        'hidden',
        'enable_user_dns_zones',
        'user_dns_zone_type'
      )
      expect(server_obj['id']).to eq(user_dns_server.id)
      expect(server_obj['enable_user_dns_zones']).to be(true)
      expect(resource_id(server_obj['node'])).to eq(user_dns_server.node_id)
    end

    it 'returns 404 for users accessing internal servers' do
      as(SpecSeed.user) { json_get show_path(internal_dns_server.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows support to show user-enabled servers' do
      as(SpecSeed.support) { json_get show_path(user_dns_server.id) }

      expect_status(200)
      expect(server_obj['id']).to eq(user_dns_server.id)
    end

    it 'returns 404 for support accessing internal servers' do
      as(SpecSeed.support) { json_get show_path(internal_dns_server.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any server' do
      as(SpecSeed.admin) { json_get show_path(internal_dns_server.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(server_obj['id']).to eq(internal_dns_server.id)
    end

    it 'returns 404 for unknown servers' do
      missing = DnsServer.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:payload) do
      suffix = SecureRandom.hex(4)

      {
        node: SpecSeed.node.id,
        name: "spec-create-#{suffix}.example.test",
        ipv4_addr: random_ipv4,
        enable_user_dns_zones: true,
        hidden: false,
        user_dns_zone_type: 'primary_type'
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, dns_server: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, dns_server: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, dns_server: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create a server with minimal payload' do
      expect do
        as(SpecSeed.admin) { json_post index_path, dns_server: payload }
      end.to change(DnsServer, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(server_obj).to be_a(Hash)
      expect(server_obj['name']).to eq(payload[:name])
      expect(server_obj['ipv4_addr']).to eq(payload[:ipv4_addr])
      expect(server_obj['hidden']).to be(false)
      expect(server_obj['enable_user_dns_zones']).to be(true)
      expect(server_obj['user_dns_zone_type']).to eq('primary_type')
      expect(resource_id(server_obj['node'])).to eq(payload[:node])

      record = DnsServer.find_by!(name: payload[:name])
      expect(record.node_id).to eq(payload[:node])
      expect(record.ipv4_addr).to eq(payload[:ipv4_addr])
      expect(record.enable_user_dns_zones).to be(true)
      expect(record.hidden).to be(false)
      expect(record.user_dns_zone_type).to eq('primary_type')
    end

    it 'returns validation errors for missing name' do
      as(SpecSeed.admin) { json_post index_path, dns_server: payload.except(:name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('name')
    end

    it 'returns validation errors for missing node' do
      as(SpecSeed.admin) { json_post index_path, dns_server: payload.except(:node) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('node')
    end

    it 'returns validation errors when no addresses are provided' do
      as(SpecSeed.admin) do
        json_post index_path, dns_server: payload.except(:ipv4_addr, :ipv6_addr)
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('ipv4_addr', 'ipv6_addr')
    end

    it 'returns validation errors for names with trailing dot' do
      suffix = SecureRandom.hex(4)
      as(SpecSeed.admin) do
        json_post index_path, dns_server: payload.merge(name: "bad-name-#{suffix}.example.test.")
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('name')
    end

    it 'returns validation errors for invalid user_dns_zone_type' do
      as(SpecSeed.admin) do
        json_post index_path, dns_server: payload.merge(user_dns_zone_type: 'invalid_type')
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('user_dns_zone_type')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(user_dns_server.id), dns_server: { hidden: true }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(user_dns_server.id), dns_server: { hidden: true } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put show_path(user_dns_server.id), dns_server: { hidden: true } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to update servers' do
      update_payload = {
        ipv4_addr: random_ipv4,
        hidden: true,
        enable_user_dns_zones: false,
        user_dns_zone_type: 'secondary_type'
      }

      as(SpecSeed.admin) { json_put show_path(user_dns_server.id), dns_server: update_payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(server_obj['ipv4_addr']).to eq(update_payload[:ipv4_addr])
      expect(server_obj['hidden']).to be(true)
      expect(server_obj['enable_user_dns_zones']).to be(false)
      expect(server_obj['user_dns_zone_type']).to eq('secondary_type')

      user_dns_server.reload
      expect(user_dns_server.ipv4_addr).to eq(update_payload[:ipv4_addr])
      expect(user_dns_server.hidden).to be(true)
      expect(user_dns_server.enable_user_dns_zones).to be(false)
      expect(user_dns_server.user_dns_zone_type).to eq('secondary_type')
    end

    it 'returns 404 for unknown servers' do
      missing = DnsServer.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_put show_path(missing), dns_server: { hidden: true } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(user_dns_server.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(user_dns_server.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_delete show_path(user_dns_server.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete servers not in use' do
      server = create_server!(name_prefix: 'spec-del', enable_user_dns_zones: true)

      as(SpecSeed.admin) { json_delete show_path(server.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(DnsServer.where(id: server.id)).to be_empty
    end

    it 'rejects deletion when server is in use' do
      server = create_server!(name_prefix: 'spec-del-use', enable_user_dns_zones: true)
      zone = create_zone!(name_prefix: 'spec-del-zone')
      attach_zone!(server: server, zone: zone)

      as(SpecSeed.admin) { json_delete show_path(server.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('DNS server is in use')
      expect(DnsServer.where(id: server.id)).not_to be_empty
    end

    it 'returns 404 for unknown servers' do
      missing = DnsServer.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
