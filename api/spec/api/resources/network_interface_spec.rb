# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::NetworkInterface' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    SpecSeed.support
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path
    vpath('/network_interfaces')
  end

  def show_path(id)
    vpath("/network_interfaces/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def netifs
    json.dig('response', 'network_interfaces') || []
  end

  def netif_obj
    json.dig('response', 'network_interface') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def response_action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
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
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_dataset_in_pool!(user:, pool:)
    dataset = Dataset.create!(
      name: "spec-#{SecureRandom.hex(4)}",
      user: user,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    )
    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    dataset_in_pool = create_dataset_in_pool!(user: user, pool: pool)

    Vps.create!(
      user: user,
      node: node,
      hostname: hostname,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active
    )
  end

  def create_netif!(vps:, name: 'eth0', kind: :veth_routed, max_tx: 0, max_rx: 0, enable: true)
    NetworkInterface.create!(
      vps: vps,
      name: name,
      kind: kind,
      max_tx: max_tx,
      max_rx: max_rx,
      enable: enable
    )
  end

  describe 'API description' do
    it 'includes network interface endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'network_interface#index',
        'network_interface#show',
        'network_interface#update'
      )
    end

    it 'documents network interface inputs' do
      index_params = action_input_params('network_interface', 'index')
      update_params = action_input_params('network_interface', 'update')

      expect(index_params.keys).to include('vps', 'location', 'user', 'limit', 'from_id')
      expect(update_params.keys).to include('name', 'max_tx', 'max_rx', 'enable')
    end
  end

  describe 'Index' do
    let(:index_data) do
      user_vps_a = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps-a')
      user_vps_b = create_vps!(user: SpecSeed.user, node: SpecSeed.other_node, hostname: 'user-vps-b')
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'other-vps')
      {
        user_vps_a: user_vps_a,
        user_vps_b: user_vps_b,
        other_vps: other_vps,
        user_netif_a: create_netif!(vps: user_vps_a),
        user_netif_b: create_netif!(vps: user_vps_b),
        other_netif: create_netif!(vps: other_vps)
      }
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows only own interfaces to users' do
      data = index_data
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to include(data[:user_netif_a].id, data[:user_netif_b].id)
      expect(ids).not_to include(data[:other_netif].id)
    end

    it 'restricts support users' do
      index_data
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to be_empty
    end

    it 'shows all interfaces to admins' do
      data = index_data
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to include(data[:user_netif_a].id, data[:user_netif_b].id, data[:other_netif].id)
    end

    it 'filters by user for admins' do
      data = index_data
      as(SpecSeed.admin) { json_get index_path, network_interface: { user: SpecSeed.user.id } }

      expect_status(200)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to contain_exactly(data[:user_netif_a].id, data[:user_netif_b].id)
    end

    it 'ignores user filter for non-admins' do
      data = index_data
      as(SpecSeed.user) { json_get index_path, network_interface: { user: SpecSeed.other_user.id } }

      expect_status(200)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to include(data[:user_netif_a].id, data[:user_netif_b].id)
      expect(ids).not_to include(data[:other_netif].id)
    end

    it 'filters by vps for admins' do
      data = index_data
      as(SpecSeed.admin) { json_get index_path, network_interface: { vps: data[:user_vps_a].id } }

      expect_status(200)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to contain_exactly(data[:user_netif_a].id)
    end

    it 'filters by vps for users' do
      data = index_data
      as(SpecSeed.user) { json_get index_path, network_interface: { vps: data[:user_vps_a].id } }

      expect_status(200)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to contain_exactly(data[:user_netif_a].id)
    end

    it 'returns empty when users filter by other vps' do
      data = index_data
      as(SpecSeed.user) { json_get index_path, network_interface: { vps: data[:other_vps].id } }

      expect_status(200)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to be_empty
    end

    it 'filters by location' do
      data = index_data
      as(SpecSeed.admin) { json_get index_path, network_interface: { location: SpecSeed.location.id } }

      expect_status(200)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to include(data[:user_netif_a].id, data[:other_netif].id)
      expect(ids).not_to include(data[:user_netif_b].id)
    end

    it 'supports limit pagination' do
      index_data
      as(SpecSeed.admin) { json_get index_path, network_interface: { limit: 1 } }

      expect_status(200)
      expect(netifs.length).to eq(1)
    end

    it 'supports from_id pagination' do
      index_data
      boundary = NetworkInterface.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, network_interface: { from_id: boundary } }

      expect_status(200)
      ids = netifs.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      index_data
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(NetworkInterface.joins(:vps).count)
    end

    it 'returns expected output shape' do
      data = index_data
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      row = netifs.find { |item| item['id'] == data[:user_netif_a].id }
      expect(row).to include('id', 'vps', 'name', 'type', 'mac', 'max_tx', 'max_rx', 'enable')
      expect(row['type']).to eq(data[:user_netif_a].kind)
      expect(resource_id(row['vps'])).to eq(data[:user_vps_a].id)
    end
  end

  describe 'Show' do
    let(:show_data) do
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps')
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'other-vps')
      {
        user_vps: user_vps,
        user_netif: create_netif!(vps: user_vps),
        other_netif: create_netif!(vps: other_vps)
      }
    end

    it 'rejects unauthenticated access' do
      data = show_data
      json_get show_path(data[:user_netif].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their netif' do
      data = show_data
      as(SpecSeed.user) { json_get show_path(data[:user_netif].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(netif_obj['id']).to eq(data[:user_netif].id)
      expect(netif_obj['name']).to eq(data[:user_netif].name)
      expect(netif_obj['type']).to eq(data[:user_netif].kind)
      expect(resource_id(netif_obj['vps'])).to eq(data[:user_vps].id)
      expect(netif_obj).to include('id', 'vps', 'name', 'type', 'mac', 'max_tx', 'max_rx', 'enable')
    end

    it 'prevents users from showing other netifs' do
      data = show_data
      as(SpecSeed.user) { json_get show_path(data[:other_netif].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any netif' do
      data = show_data
      as(SpecSeed.admin) { json_get show_path(data[:other_netif].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(netif_obj['id']).to eq(data[:other_netif].id)
    end

    it 'returns 404 for unknown netif' do
      show_data
      missing = NetworkInterface.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    let(:update_data) do
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps')
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'other-vps')
      {
        user_vps: user_vps,
        user_netif: create_netif!(vps: user_vps),
        other_netif: create_netif!(vps: other_vps)
      }
    end

    it 'rejects unauthenticated access' do
      data = update_data
      json_put show_path(data[:user_netif].id), network_interface: { name: 'eth1' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'prevents users from updating other netifs' do
      data = update_data
      as(SpecSeed.user) { json_put show_path(data[:other_netif].id), network_interface: { name: 'eth1' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows users to rename their netif' do
      data = update_data
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.user) { json_put show_path(data[:user_netif].id), network_interface: { name: 'eth1' } }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(netif_obj['name']).to eq('eth1')
      expect(response_action_state_id.to_i).to be > 0

      chain = TransactionChain.find(response_action_state_id)
      expect(chain.state).to eq('queued')
      expect(chain.user_id).to eq(SpecSeed.user.id)
      expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', data[:user_vps].id])
    end

    it 'allows admin to update shaper fields' do
      data = update_data
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.admin) do
          json_put show_path(data[:user_netif].id), network_interface: { max_tx: 123, max_rx: 456 }
        end
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(netif_obj['max_tx']).to eq(123)
      expect(netif_obj['max_rx']).to eq(456)
      expect(response_action_state_id.to_i).to be > 0
    end

    it 'allows admin to toggle enable' do
      data = update_data
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.admin) { json_put show_path(data[:user_netif].id), network_interface: { enable: false } }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(netif_obj['enable']).to be(false)
      expect(response_action_state_id.to_i).to be > 0
    end

    it 'ignores non-whitelisted fields for users' do
      data = update_data
      as(SpecSeed.user) { json_put show_path(data[:user_netif].id), network_interface: { max_tx: 999 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_action_state_id).to be_nil
      expect(netif_obj['max_tx']).to eq(0)
      expect(data[:user_netif].reload.max_tx).to eq(0)
    end

    it 'returns validation errors for invalid name' do
      data = update_data
      ensure_signer_unlocked!

      as(SpecSeed.admin) do
        json_put show_path(data[:user_netif].id), network_interface: { name: 'bad name with spaces' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('name')
    end

    it 'rejects negative max_tx' do
      data = update_data
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_put show_path(data[:user_netif].id), network_interface: { max_tx: -1 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('max_tx')
    end

    it 'rejects renaming on non-vpsadminos nodes' do
      data = update_data
      SpecSeed.node.update!(hypervisor_type: :openvz)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_put show_path(data[:user_netif].id), network_interface: { name: 'eth9' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('veth renaming is not available on this node')
    end
  end
end
