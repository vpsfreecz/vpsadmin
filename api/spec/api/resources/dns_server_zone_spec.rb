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

  def transfer_log_index_path
    vpath('/dns_server_zone_transfer_logs')
  end

  def transfer_log_show_path(log_id)
    vpath("/dns_server_zone_transfer_logs/#{log_id}")
  end

  def transfer_log_filter(server_zone)
    {
      dns_server_zone_transfer_log: {
        dns_server_zone: server_zone.id
      }
    }
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

  def transfer_logs
    json.dig('response', 'transfer_logs') ||
      json.dig('response', 'dns_server_zone_transfer_logs') ||
      json.dig('response', 'logs') ||
      []
  end

  def transfer_log_obj
    json.dig('response', 'transfer_log') ||
      json.dig('response', 'dns_server_zone_transfer_log') ||
      json['response']
  end

  def transfer_field_keys
    %w[
      last_transfer_at
      last_transfer_status
      last_transfer_reason_code
      last_transfer_reason
      last_transfer_primary_addr
      last_transfer_serial
      last_transfer_log_id
    ]
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

  def create_transfer_log!(server_zone:, status: :failed, reason_code: 'refused', event_at: Time.now)
    DnsServerZoneTransferLog.create!(
      dns_server_zone: server_zone,
      event_key: SecureRandom.hex(32),
      event_at: event_at,
      status: status,
      reason_code: reason_code,
      reason: reason_code ? 'The primary DNS server refused the transfer' : nil,
      primary_addr: '192.0.2.1',
      message: 'Transfer status: REFUSED',
      raw_message: 'raw bind message',
      source_cursor: SecureRandom.hex(16)
    )
  end

  def set_last_transfer!(server_zone, log)
    server_zone.update!(
      last_transfer_log: log,
      last_transfer_at: log.event_at,
      last_transfer_status: log.status,
      last_transfer_reason_code: log.reason_code,
      last_transfer_reason: log.reason,
      last_transfer_primary_addr: log.primary_addr,
      last_transfer_serial: log.serial
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

  let!(:server_secondary_visible) do
    create_server!(
      name: "spec-dns-secondary-#{SecureRandom.hex(4)}",
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

  let!(:sz_user_internal_secondary_visible) do
    create_server_zone!(
      dns_server: server_secondary_visible,
      dns_zone: zone_user_internal,
      zone_type: :secondary_type
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
        'dns_server_zone#delete',
        'dns_server_zone_transfer_log#index',
        'dns_server_zone_transfer_log#show'
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

    it 'hides internal transfer status fields from users only' do
      internal_log = create_transfer_log!(server_zone: sz_user_internal_secondary_visible)
      external_log = create_transfer_log!(server_zone: sz_user_external_visible)
      set_last_transfer!(sz_user_internal_secondary_visible, internal_log)
      set_last_transfer!(sz_user_external_visible, external_log)

      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      internal_row = server_zones.find { |row| row['id'] == sz_user_internal_secondary_visible.id }
      external_row = server_zones.find { |row| row['id'] == sz_user_external_visible.id }

      expect(internal_row.keys).not_to include(*transfer_field_keys)
      expect(external_row).to include(
        'last_transfer_status' => 'failed',
        'last_transfer_reason_code' => 'refused',
        'last_transfer_log_id' => external_log.id
      )

      as(SpecSeed.admin) { json_get index_path }

      admin_row = server_zones.find { |row| row['id'] == sz_user_internal_secondary_visible.id }
      expect(admin_row).to include(
        'last_transfer_status' => 'failed',
        'last_transfer_reason_code' => 'refused',
        'last_transfer_log_id' => internal_log.id
      )
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

    it 'shows the latest transfer status fields' do
      log = create_transfer_log!(server_zone: sz_user_external_visible)
      set_last_transfer!(sz_user_external_visible, log)

      as(SpecSeed.user) { json_get show_path(sz_user_external_visible.id) }

      expect_status(200)
      expect(server_zone_obj).to include(
        'last_transfer_status' => 'failed',
        'last_transfer_reason_code' => 'refused',
        'last_transfer_reason' => 'The primary DNS server refused the transfer',
        'last_transfer_primary_addr' => '192.0.2.1',
        'last_transfer_log_id' => log.id
      )
    end

    it 'hides internal transfer status fields from users only' do
      log = create_transfer_log!(server_zone: sz_user_internal_secondary_visible)
      set_last_transfer!(sz_user_internal_secondary_visible, log)

      as(SpecSeed.user) { json_get show_path(sz_user_internal_secondary_visible.id) }

      expect_status(200)
      expect(server_zone_obj.keys).not_to include(*transfer_field_keys)

      as(SpecSeed.admin) { json_get show_path(sz_user_internal_secondary_visible.id) }

      expect_status(200)
      expect(server_zone_obj).to include(
        'last_transfer_status' => 'failed',
        'last_transfer_reason_code' => 'refused',
        'last_transfer_log_id' => log.id
      )
    end

    it 'returns 404 for unknown zone' do
      missing = DnsServerZone.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'DnsServerZoneTransferLog' do
    let!(:user_log) do
      create_transfer_log!(
        server_zone: sz_user_external_visible,
        event_at: 2.hours.ago
      )
    end

    let!(:recent_user_log) do
      create_transfer_log!(
        server_zone: sz_user_external_visible,
        status: :success,
        reason_code: nil,
        event_at: 1.hour.ago
      )
    end

    let!(:support_log) do
      create_transfer_log!(server_zone: sz_support_visible)
    end

    let!(:internal_log) do
      create_transfer_log!(server_zone: sz_user_internal_secondary_visible)
    end

    it 'rejects unauthenticated access' do
      json_get transfer_log_index_path, transfer_log_filter(sz_user_external_visible)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists user logs without raw admin fields' do
      as(SpecSeed.user) { json_get transfer_log_index_path, transfer_log_filter(sz_user_external_visible) }

      expect_status(200)
      ids = transfer_logs.map { |row| row['id'] }
      expect(ids).to include(user_log.id, recent_user_log.id)
      expect(ids).not_to include(support_log.id)

      row = transfer_logs.find { |item| item['id'] == user_log.id }
      expect(row).to include('status' => 'failed', 'reason_code' => 'refused')
      expect(row).not_to include('raw_message', 'source_cursor', 'event_key')
    end

    it 'orders same-time transfer results before started logs' do
      event_at = Time.now.change(usec: 0)
      started_log = create_transfer_log!(
        server_zone: sz_user_external_visible,
        status: :started,
        reason_code: nil,
        event_at:
      )
      result_log = create_transfer_log!(
        server_zone: sz_user_external_visible,
        status: :success,
        reason_code: nil,
        event_at:
      )

      as(SpecSeed.user) { json_get transfer_log_index_path, transfer_log_filter(sz_user_external_visible) }

      expect_status(200)
      ids = transfer_logs.map { |row| row['id'] }
      expect(ids.index(result_log.id)).to be < ids.index(started_log.id)
    end

    it 'filters user logs by DNS zone' do
      as(SpecSeed.user) do
        json_get transfer_log_index_path, {
          dns_server_zone_transfer_log: { dns_zone: zone_user_external.id }
        }
      end

      expect_status(200)
      ids = transfer_logs.map { |row| row['id'] }
      expect(ids).to include(user_log.id, recent_user_log.id)
      expect(ids).not_to include(support_log.id, internal_log.id)
    end

    it 'does not expose internal zone transfer logs to users' do
      as(SpecSeed.user) do
        json_get transfer_log_index_path, transfer_log_filter(sz_user_internal_secondary_visible)
      end

      expect_status(200)
      expect(transfer_logs.map { |row| row['id'] }).not_to include(internal_log.id)

      as(SpecSeed.user) do
        json_get transfer_log_show_path(internal_log.id)
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to see raw fields' do
      as(SpecSeed.admin) { json_get transfer_log_show_path(user_log.id) }

      expect_status(200)
      expect(transfer_log_obj).to include(
        'id' => user_log.id,
        'raw_message' => 'raw bind message',
        'source_cursor' => user_log.source_cursor,
        'event_key' => user_log.event_key
      )
    end

    it 'allows admins to see internal zone transfer logs' do
      as(SpecSeed.admin) do
        json_get transfer_log_index_path, transfer_log_filter(sz_user_internal_secondary_visible)
      end

      expect_status(200)
      expect(transfer_logs.map { |row| row['id'] }).to include(internal_log.id)

      as(SpecSeed.admin) do
        json_get transfer_log_show_path(internal_log.id)
      end

      expect_status(200)
      expect(transfer_log_obj).to include(
        'id' => internal_log.id,
        'raw_message' => 'raw bind message',
        'source_cursor' => internal_log.source_cursor,
        'event_key' => internal_log.event_key
      )
    end

    it 'filters admin logs by DNS zone' do
      as(SpecSeed.admin) do
        json_get transfer_log_index_path, {
          dns_server_zone_transfer_log: { dns_zone: zone_user_internal.id }
        }
      end

      expect_status(200)
      ids = transfer_logs.map { |row| row['id'] }
      expect(ids).to include(internal_log.id)
      expect(ids).not_to include(user_log.id, recent_user_log.id, support_log.id)
    end

    it 'does not expose hidden server logs to users' do
      hidden_log = create_transfer_log!(server_zone: sz_user_hidden)

      as(SpecSeed.user) { json_get transfer_log_show_path(hidden_log.id) }

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
