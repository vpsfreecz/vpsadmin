# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::DnsServerZone' do
  before do
    header 'Accept', 'application/json'

    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.other_user
    SpecSeed.node
  end

  def index_path
    vpath('/dns_server_zones')
  end

  def show_path(id)
    vpath("/dns_server_zones/#{id}")
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

  def json_delete(path)
    delete path, nil, { 'CONTENT_TYPE' => 'application/json' }
  end

  def server_zones
    json.dig('response', 'dns_server_zones') || []
  end

  def server_zone_obj
    json.dig('response', 'dns_server_zone') || json['response']
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

  def create_server!(name:, node:, hidden: false, enable_user_dns_zones: true)
    DnsServer.create!(
      node: node,
      name: name,
      ipv4_addr: '192.0.2.10',
      ipv6_addr: nil,
      hidden: hidden,
      enable_user_dns_zones: enable_user_dns_zones,
      user_dns_zone_type: :primary_type
    )
  end

  def create_zone!(name:, user: nil, source: :internal_source, role: :forward_role, enabled: true,
                   email: 'dns@example.test')
    DnsZone.create!(
      name: name,
      user: user,
      zone_role: role,
      zone_source: source,
      enabled: enabled,
      label: '',
      default_ttl: 3600,
      email: email,
      reverse_network_address: nil,
      reverse_network_prefix: nil
    )
  end

  def create_server_zone!(dns_server:, dns_zone:, zone_type: :primary_type)
    DnsServerZone.create!(
      dns_server: dns_server,
      dns_zone: dns_zone,
      zone_type: zone_type,
      confirmed: DnsServerZone.confirmed(:confirm_create)
    )
  end

  let!(:server_visible) do
    create_server!(
      name: "spec-dns-#{SecureRandom.hex(4)}",
      node: SpecSeed.node,
      hidden: false,
      enable_user_dns_zones: true
    )
  end

  let!(:server_hidden) do
    create_server!(
      name: "spec-dns-#{SecureRandom.hex(4)}",
      node: SpecSeed.node,
      hidden: true,
      enable_user_dns_zones: true
    )
  end

  let!(:zone_user_internal) do
    create_zone!(
      name: "spec-user-int-#{SecureRandom.hex(4)}.example.test.",
      user: SpecSeed.user,
      source: :internal_source,
      email: 'user@example.test'
    )
  end

  let!(:zone_user_external) do
    create_zone!(
      name: "spec-user-ext-#{SecureRandom.hex(4)}.example.test.",
      user: SpecSeed.user,
      source: :external_source,
      email: nil
    )
  end

  let!(:zone_support_internal) do
    create_zone!(
      name: "spec-support-#{SecureRandom.hex(4)}.example.test.",
      user: SpecSeed.support,
      source: :internal_source,
      email: 'support@example.test'
    )
  end

  let!(:zone_system_internal) do
    create_zone!(
      name: "spec-system-#{SecureRandom.hex(4)}.example.test.",
      user: nil,
      source: :internal_source,
      email: 'admin@example.test'
    )
  end

  let!(:sz_user_visible) do
    create_server_zone!(
      dns_server: server_visible,
      dns_zone: zone_user_internal,
      zone_type: :primary_type
    )
  end

  let!(:sz_user_hidden) do
    create_server_zone!(
      dns_server: server_hidden,
      dns_zone: zone_user_internal,
      zone_type: :primary_type
    )
  end

  let!(:sz_user_external_visible) do
    create_server_zone!(
      dns_server: server_visible,
      dns_zone: zone_user_external,
      zone_type: :secondary_type
    )
  end

  let!(:sz_support_visible) do
    create_server_zone!(
      dns_server: server_visible,
      dns_zone: zone_support_internal,
      zone_type: :primary_type
    )
  end

  let!(:sz_system_visible) do
    create_server_zone!(
      dns_server: server_visible,
      dns_zone: zone_system_internal,
      zone_type: :primary_type
    )
  end

  describe 'API description' do
    it 'includes dns_server_zone endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'dns_server_zone#index',
        'dns_server_zone#show',
        'dns_server_zone#create',
        'dns_server_zone#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists user zones on visible servers only' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(server_zones).to be_an(Array)

      ids = server_zones.map { |row| row['id'] }
      expect(ids).to include(sz_user_visible.id, sz_user_external_visible.id)
      expect(ids).not_to include(sz_user_hidden.id, sz_support_visible.id, sz_system_visible.id)

      row = server_zones.find { |item| item['id'] == sz_user_visible.id }
      expect(row).to include('id', 'dns_server', 'dns_zone', 'type')
      expect(rid(row['dns_server'])).to eq(server_visible.id)
      expect(rid(row['dns_zone'])).to eq(zone_user_internal.id)
    end

    it 'restricts support to their own zones' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      ids = server_zones.map { |row| row['id'] }
      expect(ids).to include(sz_support_visible.id)
      expect(ids).not_to include(sz_user_visible.id)
    end

    it 'allows admins to list all server zones' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = server_zones.map { |row| row['id'] }
      expect(ids).to include(
        sz_user_visible.id,
        sz_user_hidden.id,
        sz_user_external_visible.id,
        sz_support_visible.id,
        sz_system_visible.id
      )
    end

    it 'filters by dns_server' do
      as(SpecSeed.admin) do
        json_get index_path, dns_server_zone: { dns_server: server_visible.id }
      end

      expect_status(200)
      ids = server_zones.map { |row| row['id'] }
      expect(ids).to include(
        sz_user_visible.id,
        sz_user_external_visible.id,
        sz_support_visible.id,
        sz_system_visible.id
      )
      expect(ids).not_to include(sz_user_hidden.id)
    end

    it 'filters by dns_zone' do
      as(SpecSeed.admin) do
        json_get index_path, dns_server_zone: { dns_zone: zone_user_internal.id }
      end

      expect_status(200)
      ids = server_zones.map { |row| row['id'] }
      expect(ids).to include(sz_user_visible.id, sz_user_hidden.id)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, dns_server_zone: { limit: 1 } }

      expect_status(200)
      expect(server_zones.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = DnsServerZone.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, dns_server_zone: { from_id: boundary } }

      expect_status(200)
      ids = server_zones.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(DnsServerZone.existing.count)
    end

    it 'returns validation errors for invalid type' do
      as(SpecSeed.admin) { json_get index_path, dns_server_zone: { type: 'NOPE' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('type')
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(sz_user_visible.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their zone on visible servers' do
      as(SpecSeed.user) { json_get show_path(sz_user_visible.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(server_zone_obj).to include('id', 'dns_server', 'dns_zone', 'type')
      expect(server_zone_obj['id']).to eq(sz_user_visible.id)
      expect(rid(server_zone_obj['dns_server'])).to eq(server_visible.id)
      expect(rid(server_zone_obj['dns_zone'])).to eq(zone_user_internal.id)
      expect(server_zone_obj['type']).to eq('primary_type')
    end

    it 'returns 404 for users accessing zones on hidden servers' do
      as(SpecSeed.user) { json_get show_path(sz_user_hidden.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for users accessing support or system zones' do
      as(SpecSeed.user) { json_get show_path(sz_support_visible.id) }

      expect_status(404)
      expect(json['status']).to be(false)

      as(SpecSeed.user) { json_get show_path(sz_system_visible.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show zones on hidden servers' do
      as(SpecSeed.admin) { json_get show_path(sz_user_hidden.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown zone' do
      missing = DnsServerZone.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:new_zone) do
      create_zone!(
        name: "spec-new-#{SecureRandom.hex(4)}.example.test.",
        user: SpecSeed.user,
        source: :internal_source,
        email: 'user@example.test'
      )
    end

    let(:payload) do
      {
        dns_server: server_visible.id,
        dns_zone: new_zone.id,
        type: 'primary_type'
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, dns_server_zone: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids users and support' do
      as(SpecSeed.user) { json_post index_path, dns_server_zone: payload }

      expect_status(403)
      expect(json['status']).to be(false)

      as(SpecSeed.support) { json_post index_path, dns_server_zone: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create a server zone' do
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.admin) { json_post index_path, dns_server_zone: payload }
      end.to change(DnsServerZone, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(server_zone_obj).to include('dns_server', 'dns_zone', 'type')
      expect(rid(server_zone_obj['dns_server'])).to eq(server_visible.id)
      expect(rid(server_zone_obj['dns_zone'])).to eq(new_zone.id)
      expect(server_zone_obj['type']).to eq('primary_type')

      record = DnsServerZone.find_by!(dns_server_id: server_visible.id, dns_zone_id: new_zone.id)
      expect(record.zone_type).to eq('primary_type')
      expect(record.confirmed).to eq(:confirm_create)
    end

    it 'returns validation errors for missing dns_zone' do
      as(SpecSeed.admin) { json_post index_path, dns_server_zone: payload.except(:dns_zone) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('dns_zone')
    end

    it 'returns validation errors for missing dns_server' do
      as(SpecSeed.admin) { json_post index_path, dns_server_zone: payload.except(:dns_server) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('dns_server')
    end

    it 'returns validation errors for invalid type' do
      as(SpecSeed.admin) { json_post index_path, dns_server_zone: payload.merge(type: 'NOPE') }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('type')
    end

    it 'rejects external zones as primary' do
      external_zone = create_zone!(
        name: "spec-ext-#{SecureRandom.hex(4)}.example.test.",
        user: SpecSeed.user,
        source: :external_source,
        email: nil
      )

      as(SpecSeed.admin) do
        json_post index_path, dns_server_zone: payload.merge(dns_zone: external_zone.id)
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('type')
    end

    it 'rejects duplicate server zone entries' do
      as(SpecSeed.admin) do
        json_post index_path, dns_server_zone: {
          dns_server: server_visible.id,
          dns_zone: zone_user_internal.id,
          type: 'primary_type'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('already is on server')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(sz_user_visible.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids users and support' do
      as(SpecSeed.user) { json_delete show_path(sz_user_visible.id) }

      expect_status(403)
      expect(json['status']).to be(false)

      as(SpecSeed.support) { json_delete show_path(sz_user_visible.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete server zones' do
      to_delete = create_server_zone!(
        dns_server: server_visible,
        dns_zone: create_zone!(
          name: "spec-del-#{SecureRandom.hex(4)}.example.test.",
          user: SpecSeed.user,
          source: :internal_source,
          email: 'user@example.test'
        ),
        zone_type: :primary_type
      )

      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_delete show_path(to_delete.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(DnsServerZone.existing.where(id: to_delete.id)).to be_empty
      expect(DnsServerZone.find(to_delete.id).confirmed).to eq(:confirm_destroy)
    end

    it 'returns 404 for unknown zone' do
      missing = DnsServerZone.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
