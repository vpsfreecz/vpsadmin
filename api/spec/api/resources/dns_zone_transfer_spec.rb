# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::DnsZoneTransfer' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.location
    SpecSeed.node
    SpecSeed.network_v4
  end

  def index_path
    vpath('/dns_zone_transfers')
  end

  def show_path(id)
    vpath("/dns_zone_transfers/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def transfers
    json.dig('response', 'dns_zone_transfers') || []
  end

  def transfer_obj
    json.dig('response', 'dns_zone_transfer') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def ensure_node_current_status(node = SpecSeed.node)
    NodeCurrentStatus.find_or_create_by!(node:) do |st|
      st.vpsadmin_version = 'test'
      st.kernel = 'test'
      st.update_count = 1
    end
  end

  def create_zone!(user:, source:, name: nil)
    DnsZone.create!(
      name: name || "spec-#{SecureRandom.hex(4)}.example.test.",
      user: user,
      zone_role: :forward_role,
      zone_source: source,
      enabled: true,
      label: '',
      default_ttl: 3600,
      email: (source.to_sym == :internal_source ? 'dns@example.test' : 'user@example.test')
    )
  end

  def create_dns_server!(name: nil, node: SpecSeed.node)
    DnsServer.create!(
      node: node,
      name: name || "spec-dns-#{SecureRandom.hex(3)}",
      ipv4_addr: '192.0.2.53'
    )
  end

  def create_dns_server_zone!(dns_zone:, dns_server:, zone_type:)
    DnsServerZone.create!(
      dns_zone: dns_zone,
      dns_server: dns_server,
      zone_type: zone_type
    )
  end

  def create_host_ip_for_user!(user:, ip: nil)
    net = SpecSeed.network_v4
    ip_addr = ip || "192.0.2.#{rand(100..250)}"

    ip_record = IpAddress.create!(
      network: net,
      ip_addr: ip_addr,
      prefix: net.split_prefix,
      size: 1,
      user: user
    )

    HostIpAddress.create!(
      ip_address: ip_record,
      ip_addr: ip_addr,
      order: nil,
      user_created: true
    )
  end

  def create_tsig_key!(user:, name: nil)
    DnsTsigKey.create!(
      user: user,
      name: name || "spec-key-#{SecureRandom.hex(3)}",
      algorithm: 'hmac-sha256',
      secret: 'dGVzdA=='
    )
  end

  describe 'API description' do
    it 'includes dns zone transfer endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'dns_zone_transfer#index',
        'dns_zone_transfer#show',
        'dns_zone_transfer#create',
        'dns_zone_transfer#delete'
      )
    end
  end

  describe 'Index' do
    let(:index_seed) do
      user_zone_ext = create_zone!(user: SpecSeed.user, source: :external_source)
      user_zone_int = create_zone!(user: SpecSeed.user, source: :internal_source)
      other_zone_ext = create_zone!(user: SpecSeed.other_user, source: :external_source)
      user_host_ip_a = create_host_ip_for_user!(user: SpecSeed.user)
      user_host_ip_b = create_host_ip_for_user!(user: SpecSeed.user)
      other_host_ip = create_host_ip_for_user!(user: SpecSeed.other_user)
      user_key_a = create_tsig_key!(user: SpecSeed.user)
      user_key_b = create_tsig_key!(user: SpecSeed.user)
      other_key = create_tsig_key!(user: SpecSeed.other_user)

      transfer_user_ext = DnsZoneTransfer.create!(
        dns_zone: user_zone_ext,
        host_ip_address: user_host_ip_a,
        peer_type: :primary_type,
        dns_tsig_key: user_key_a
      )
      transfer_user_int = DnsZoneTransfer.create!(
        dns_zone: user_zone_int,
        host_ip_address: user_host_ip_b,
        peer_type: :secondary_type,
        dns_tsig_key: user_key_b
      )
      transfer_other_ext = DnsZoneTransfer.create!(
        dns_zone: other_zone_ext,
        host_ip_address: other_host_ip,
        peer_type: :primary_type,
        dns_tsig_key: other_key
      )

      {
        user_zone_ext: user_zone_ext,
        user_zone_int: user_zone_int,
        other_zone_ext: other_zone_ext,
        user_host_ip_a: user_host_ip_a,
        user_host_ip_b: user_host_ip_b,
        other_host_ip: other_host_ip,
        user_key_a: user_key_a,
        user_key_b: user_key_b,
        other_key: other_key,
        transfer_user_ext: transfer_user_ext,
        transfer_user_int: transfer_user_int,
        transfer_other_ext: transfer_other_ext
      }
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists transfers for zones owned by the user' do
      seed = index_seed
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(transfers).to be_an(Array)

      ids = transfers.map { |row| row['id'] }
      expect(ids).to include(seed[:transfer_user_ext].id, seed[:transfer_user_int].id)
      expect(ids).not_to include(seed[:transfer_other_ext].id)
    end

    it 'allows admins to list all transfers' do
      seed = index_seed
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = transfers.map { |row| row['id'] }
      expect(ids).to include(
        seed[:transfer_user_ext].id,
        seed[:transfer_user_int].id,
        seed[:transfer_other_ext].id
      )
    end

    it 'filters by dns_zone' do
      seed = index_seed
      as(SpecSeed.admin) { json_get index_path, dns_zone_transfer: { dns_zone: seed[:user_zone_ext].id } }

      expect_status(200)
      ids = transfers.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:transfer_user_ext].id)
    end

    it 'filters by host_ip_address' do
      seed = index_seed
      as(SpecSeed.admin) do
        json_get index_path, dns_zone_transfer: { host_ip_address: seed[:user_host_ip_b].id }
      end

      expect_status(200)
      ids = transfers.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:transfer_user_int].id)
    end

    it 'filters by peer_type' do
      seed = index_seed
      as(SpecSeed.admin) { json_get index_path, dns_zone_transfer: { peer_type: 'secondary_type' } }

      expect_status(200)
      ids = transfers.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:transfer_user_int].id)
    end

    it 'filters by dns_tsig_key' do
      seed = index_seed
      as(SpecSeed.admin) { json_get index_path, dns_zone_transfer: { dns_tsig_key: seed[:user_key_a].id } }

      expect_status(200)
      ids = transfers.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:transfer_user_ext].id)
    end

    it 'supports limit pagination' do
      index_seed
      as(SpecSeed.admin) { json_get index_path, dns_zone_transfer: { limit: 1 } }

      expect_status(200)
      expect(transfers.length).to eq(1)
    end

    it 'supports from_id pagination' do
      index_seed
      boundary = DnsZoneTransfer.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, dns_zone_transfer: { from_id: boundary } }

      expect_status(200)
      ids = transfers.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      index_seed
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(DnsZoneTransfer.existing.count)
    end
  end

  describe 'Show' do
    let(:show_seed) do
      user_zone = create_zone!(user: SpecSeed.user, source: :external_source)
      other_zone = create_zone!(user: SpecSeed.other_user, source: :external_source)
      user_host_ip = create_host_ip_for_user!(user: SpecSeed.user)
      other_host_ip = create_host_ip_for_user!(user: SpecSeed.other_user)
      user_key = create_tsig_key!(user: SpecSeed.user)
      other_key = create_tsig_key!(user: SpecSeed.other_user)
      user_transfer = DnsZoneTransfer.create!(
        dns_zone: user_zone,
        host_ip_address: user_host_ip,
        peer_type: :primary_type,
        dns_tsig_key: user_key
      )
      other_transfer = DnsZoneTransfer.create!(
        dns_zone: other_zone,
        host_ip_address: other_host_ip,
        peer_type: :primary_type,
        dns_tsig_key: other_key
      )

      {
        user_zone: user_zone,
        other_zone: other_zone,
        user_host_ip: user_host_ip,
        other_host_ip: other_host_ip,
        user_key: user_key,
        other_key: other_key,
        user_transfer: user_transfer,
        other_transfer: other_transfer
      }
    end

    it 'rejects unauthenticated access' do
      seed = show_seed
      json_get show_path(seed[:user_transfer].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their transfer' do
      seed = show_seed
      as(SpecSeed.user) { json_get show_path(seed[:user_transfer].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(transfer_obj).to include(
        'id',
        'dns_zone',
        'host_ip_address',
        'peer_type',
        'created_at',
        'updated_at'
      )
      expect(transfer_obj['id']).to eq(seed[:user_transfer].id)
      expect(rid(transfer_obj['dns_zone'])).to eq(seed[:user_zone].id)
      expect(rid(transfer_obj['host_ip_address'])).to eq(seed[:user_host_ip].id)
      expect(transfer_obj['peer_type']).to eq('primary_type')
    end

    it 'returns 404 for users accessing other transfers' do
      seed = show_seed
      as(SpecSeed.user) { json_get show_path(seed[:other_transfer].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any transfer' do
      seed = show_seed
      as(SpecSeed.admin) { json_get show_path(seed[:other_transfer].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(transfer_obj['id']).to eq(seed[:other_transfer].id)
    end

    it 'returns 404 for unknown transfer' do
      missing = DnsZoneTransfer.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    before do
      ensure_signer_unlocked!
      ensure_node_current_status
    end

    it 'rejects unauthenticated access' do
      zone = create_zone!(user: SpecSeed.user, source: :external_source)
      dns_server = create_dns_server!
      create_dns_server_zone!(dns_zone: zone, dns_server: dns_server, zone_type: :secondary_type)
      host_ip = create_host_ip_for_user!(user: SpecSeed.user)
      key = create_tsig_key!(user: SpecSeed.user)

      json_post index_path, dns_zone_transfer: {
        dns_zone: zone.id,
        host_ip_address: host_ip.id,
        peer_type: 'primary_type',
        dns_tsig_key: key.id
      }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to create transfers for their external zone' do
      zone = create_zone!(user: SpecSeed.user, source: :external_source)
      dns_server = create_dns_server!
      create_dns_server_zone!(dns_zone: zone, dns_server: dns_server, zone_type: :secondary_type)
      host_ip = create_host_ip_for_user!(user: SpecSeed.user)
      key = create_tsig_key!(user: SpecSeed.user)

      payload = {
        dns_zone: zone.id,
        host_ip_address: host_ip.id,
        peer_type: 'primary_type',
        dns_tsig_key: key.id
      }

      expect do
        as(SpecSeed.user) { json_post index_path, dns_zone_transfer: payload }
      end.to change(DnsZoneTransfer, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(transfer_obj).to be_a(Hash)
      expect(transfer_obj['peer_type']).to eq('primary_type')
      expect(action_state_id.to_i).to be > 0
    end

    it 'prevents users from creating transfers for system zones' do
      zone = create_zone!(user: nil, source: :external_source)
      dns_server = create_dns_server!
      create_dns_server_zone!(dns_zone: zone, dns_server: dns_server, zone_type: :secondary_type)
      host_ip = create_host_ip_for_user!(user: SpecSeed.user)
      key = create_tsig_key!(user: SpecSeed.user)

      as(SpecSeed.user) do
        json_post index_path, dns_zone_transfer: {
          dns_zone: zone.id,
          host_ip_address: host_ip.id,
          peer_type: 'primary_type',
          dns_tsig_key: key.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('access denied')
    end

    it 'rejects primary_type for internal zones' do
      zone = create_zone!(user: SpecSeed.user, source: :internal_source)
      host_ip = create_host_ip_for_user!(user: SpecSeed.user)
      key = create_tsig_key!(user: SpecSeed.user)

      as(SpecSeed.user) do
        json_post index_path, dns_zone_transfer: {
          dns_zone: zone.id,
          host_ip_address: host_ip.id,
          peer_type: 'primary_type',
          dns_tsig_key: key.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('peer_type')
    end

    it 'rejects transfers with host_ip_address ownership mismatch' do
      zone = create_zone!(user: SpecSeed.user, source: :external_source)
      host_ip = create_host_ip_for_user!(user: SpecSeed.other_user)
      key = create_tsig_key!(user: SpecSeed.user)

      as(SpecSeed.user) do
        json_post index_path, dns_zone_transfer: {
          dns_zone: zone.id,
          host_ip_address: host_ip.id,
          peer_type: 'primary_type',
          dns_tsig_key: key.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('host_ip_address')
    end

    it 'rejects transfers with TSIG key ownership mismatch' do
      zone = create_zone!(user: SpecSeed.user, source: :external_source)
      host_ip = create_host_ip_for_user!(user: SpecSeed.user)
      key = create_tsig_key!(user: SpecSeed.other_user)

      as(SpecSeed.user) do
        json_post index_path, dns_zone_transfer: {
          dns_zone: zone.id,
          host_ip_address: host_ip.id,
          peer_type: 'primary_type',
          dns_tsig_key: key.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('dns_tsig_key')
    end

    it 'rejects duplicate transfers between the same zone and host' do
      zone = create_zone!(user: SpecSeed.user, source: :external_source)
      dns_server = create_dns_server!
      create_dns_server_zone!(dns_zone: zone, dns_server: dns_server, zone_type: :secondary_type)
      host_ip = create_host_ip_for_user!(user: SpecSeed.user)
      key = create_tsig_key!(user: SpecSeed.user)

      payload = {
        dns_zone: zone.id,
        host_ip_address: host_ip.id,
        peer_type: 'primary_type',
        dns_tsig_key: key.id
      }

      DnsZoneTransfer.create!(
        dns_zone: zone,
        host_ip_address: host_ip,
        peer_type: :primary_type,
        dns_tsig_key: key
      )

      expect do
        as(SpecSeed.user) { json_post index_path, dns_zone_transfer: payload }
      end.not_to change(DnsZoneTransfer, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('already exists')
    end

    it 'returns validation errors for missing required fields' do
      as(SpecSeed.admin) { json_post index_path, dns_zone_transfer: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('host_ip_address')
    end
  end

  describe 'Delete' do
    before do
      ensure_signer_unlocked!
      ensure_node_current_status
    end

    let(:delete_seed) do
      dns_server = create_dns_server!
      user_zone = create_zone!(user: SpecSeed.user, source: :external_source)
      other_zone = create_zone!(user: SpecSeed.other_user, source: :external_source)
      user_host_ip = create_host_ip_for_user!(user: SpecSeed.user)
      other_host_ip = create_host_ip_for_user!(user: SpecSeed.other_user)
      user_key = create_tsig_key!(user: SpecSeed.user)
      other_key = create_tsig_key!(user: SpecSeed.other_user)

      create_dns_server_zone!(dns_zone: user_zone, dns_server: dns_server, zone_type: :secondary_type)
      create_dns_server_zone!(dns_zone: other_zone, dns_server: dns_server, zone_type: :secondary_type)

      user_transfer = DnsZoneTransfer.create!(
        dns_zone: user_zone,
        host_ip_address: user_host_ip,
        peer_type: :primary_type,
        dns_tsig_key: user_key
      )
      other_transfer = DnsZoneTransfer.create!(
        dns_zone: other_zone,
        host_ip_address: other_host_ip,
        peer_type: :primary_type,
        dns_tsig_key: other_key
      )

      {
        user_transfer: user_transfer,
        other_transfer: other_transfer
      }
    end

    it 'rejects unauthenticated access' do
      seed = delete_seed
      json_delete show_path(seed[:user_transfer].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to delete their transfer' do
      seed = delete_seed
      as(SpecSeed.user) { json_delete show_path(seed[:user_transfer].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(DnsZoneTransfer.existing.where(id: seed[:user_transfer].id)).not_to exist
    end

    it 'returns 404 for users deleting other transfers' do
      seed = delete_seed
      as(SpecSeed.user) { json_delete show_path(seed[:other_transfer].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete any transfer' do
      seed = delete_seed
      as(SpecSeed.admin) { json_delete show_path(seed[:other_transfer].id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown transfer' do
      missing = DnsZoneTransfer.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
