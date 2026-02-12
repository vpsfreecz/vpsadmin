# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::IpAddress' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.network_v4
    SpecSeed.network_v6
  end

  def index_path
    vpath('/ip_addresses')
  end

  def show_path(id)
    vpath("/ip_addresses/#{id}")
  end

  def assign_path(id)
    vpath("/ip_addresses/#{id}/assign")
  end

  def assign_with_host_path(id)
    vpath("/ip_addresses/#{id}/assign_with_host_address")
  end

  def free_path(id)
    vpath("/ip_addresses/#{id}/free")
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

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def ip_list
    json.dig('response', 'ip_addresses') || []
  end

  def ip_obj
    json.dig('response', 'ip_address') || json['response']
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

  def create_vps!(user:, node:, hostname:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    dataset_in_pool = create_dataset_in_pool!(user: user, pool: pool)

    Vps.create!(
      user:,
      node:,
      hostname:,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active
    )
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

  def allocate_ip_resource!(user:, environment:, size: 1)
    user_env = user.environment_user_configs.find_by!(environment: environment)
    user_env.reallocate_resource!(
      :ipv4,
      user_env.ipv4 + size,
      user: user,
      save: true,
      confirmed: ::ClusterResourceUse.confirmed(:confirmed)
    )
  end

  def create_netif!(vps:, name: 'eth0')
    NetworkInterface.create!(vps:, name:, kind: :veth_routed)
  end

  def create_ip!(addr:, network:, user: nil, netif: nil)
    ip = IpAddress.create!(
      ip_addr: addr,
      prefix: network.split_prefix,
      size: 1,
      network:,
      user:,
      network_interface: netif
    )
    HostIpAddress.create!(
      ip_address: ip,
      ip_addr: addr,
      auto_add: true,
      order: nil
    )
    ip
  end

  describe 'API description' do
    it 'includes ip address endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'ip_address#index',
        'ip_address#show',
        'ip_address#create',
        'ip_address#update',
        'ip_address#assign',
        'ip_address#assign_with_host_address',
        'ip_address#free'
      )
    end

    it 'documents ip address inputs' do
      create_params = action_input_params('ip_address', 'create')
      update_params = action_input_params('ip_address', 'update')
      assign_params = action_input_params('ip_address', 'assign')
      assign_with_params = action_input_params('ip_address', 'assign_with_host_address')

      expect(create_params.keys).to include('addr', 'network', 'user', 'location')
      expect(update_params.keys).to include('user', 'environment')
      expect(assign_params.keys).to include('network_interface')
      expect(assign_with_params.keys).to include('network_interface', 'host_ip_address')
    end
  end

  describe 'Index' do
    let(:index_data) do
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps')
      user_netif = create_netif!(vps: user_vps)
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'other-vps')
      other_netif = create_netif!(vps: other_vps)
      {
        ip_free: create_ip!(addr: '192.0.2.10', network: SpecSeed.network_v4),
        ip_user_owned: create_ip!(addr: '192.0.2.11', network: SpecSeed.network_v4, user: SpecSeed.user),
        ip_other_owned: create_ip!(addr: '192.0.2.12', network: SpecSeed.network_v4, user: SpecSeed.other_user),
        ip_user_routed: create_ip!(addr: '192.0.2.13', network: SpecSeed.network_v4, netif: user_netif),
        ip_other_routed: create_ip!(addr: '192.0.2.14', network: SpecSeed.network_v4, netif: other_netif)
      }
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows accessible addresses for normal users' do
      data = index_data
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = ip_list.map { |row| row['id'] }
      expect(ids).to include(data[:ip_free].id, data[:ip_user_owned].id, data[:ip_user_routed].id)
      expect(ids).not_to include(data[:ip_other_owned].id, data[:ip_other_routed].id)
    end

    it 'shows accessible addresses for support users' do
      data = index_data
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = ip_list.map { |row| row['id'] }
      expect(ids).to include(data[:ip_free].id)
      expect(ids).not_to include(
        data[:ip_user_owned].id,
        data[:ip_user_routed].id,
        data[:ip_other_owned].id,
        data[:ip_other_routed].id
      )
    end

    it 'shows all addresses for admins' do
      data = index_data
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = ip_list.map { |row| row['id'] }
      expect(ids).to include(
        data[:ip_free].id,
        data[:ip_user_owned].id,
        data[:ip_other_owned].id,
        data[:ip_user_routed].id,
        data[:ip_other_routed].id
      )
    end
  end

  describe 'Show' do
    let(:show_data) do
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps')
      user_netif = create_netif!(vps: user_vps)
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'other-vps')
      other_netif = create_netif!(vps: other_vps)
      {
        ip_free: create_ip!(addr: '192.0.2.20', network: SpecSeed.network_v4),
        ip_user_owned: create_ip!(addr: '192.0.2.21', network: SpecSeed.network_v4, user: SpecSeed.user),
        ip_other_owned: create_ip!(addr: '192.0.2.22', network: SpecSeed.network_v4, user: SpecSeed.other_user),
        ip_user_routed: create_ip!(addr: '192.0.2.23', network: SpecSeed.network_v4, netif: user_netif),
        ip_other_routed: create_ip!(addr: '192.0.2.24', network: SpecSeed.network_v4, netif: other_netif)
      }
    end

    it 'rejects unauthenticated access' do
      json_get show_path(show_data[:ip_free].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show free addresses' do
      as(SpecSeed.user) { json_get show_path(show_data[:ip_free].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ip_obj['id']).to eq(show_data[:ip_free].id)
    end

    it 'allows users to show owned addresses' do
      as(SpecSeed.user) { json_get show_path(show_data[:ip_user_owned].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ip_obj['id']).to eq(show_data[:ip_user_owned].id)
    end

    it 'allows users to show routed addresses assigned to their VPS' do
      as(SpecSeed.user) { json_get show_path(show_data[:ip_user_routed].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ip_obj['id']).to eq(show_data[:ip_user_routed].id)
    end

    it 'denies access to other users owned addresses' do
      as(SpecSeed.user) { json_get show_path(show_data[:ip_other_owned].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'denies access to other users routed addresses' do
      as(SpecSeed.user) { json_get show_path(show_data[:ip_other_routed].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any address' do
      as(SpecSeed.admin) { json_get show_path(show_data[:ip_other_owned].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ip_obj['id']).to eq(show_data[:ip_other_owned].id)
    end

    it 'allows admins to show routed addresses' do
      as(SpecSeed.admin) { json_get show_path(show_data[:ip_other_routed].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ip_obj['id']).to eq(show_data[:ip_other_routed].id)
    end
  end

  describe 'Create' do
    let(:payload) { { addr: '192.0.2.200', network: SpecSeed.network_v4.id } }

    it 'rejects unauthenticated access' do
      json_post index_path, ip_address: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, ip_address: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, ip_address: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create an unowned address' do
      host_count = HostIpAddress.count

      expect do
        as(SpecSeed.admin) { json_post index_path, ip_address: payload }
      end.to change(IpAddress, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(HostIpAddress.count).to eq(host_count + 1)

      record = IpAddress.find_by!(ip_addr: payload[:addr])
      expect(record.network_id).to eq(SpecSeed.network_v4.id)
      expect(record.addr).to eq(payload[:addr])
    end

    it 'returns validation errors for invalid address' do
      as(SpecSeed.admin) { json_post index_path, ip_address: payload.merge(addr: 'not-an-ip') }

      expect_status(200)
      expect(json['status']).to be(false)
      keys = response_errors.keys.map(&:to_s)
      expect(keys).to(satisfy { |list| list.include?('addr') || list.include?('ip_addr') })
    end

    it 'rejects address outside of network' do
      as(SpecSeed.admin) { json_post index_path, ip_address: payload.merge(addr: '198.51.100.10') }

      expect_status(200)
      expect(json['status']).to be(false)
    end

    it 'rejects duplicate addresses' do
      create_ip!(addr: payload[:addr], network: SpecSeed.network_v4)

      as(SpecSeed.admin) { json_post index_path, ip_address: payload }

      expect_status(200)
      expect(json['status']).to be(false)
    end

    it 'requires location when user is provided' do
      as(SpecSeed.admin) do
        json_post index_path, ip_address: payload.merge(user: SpecSeed.user.id)
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('provide location together with user')
    end

    it 'rejects networks unavailable in selected location' do
      as(SpecSeed.admin) do
        json_post index_path, ip_address: payload.merge(
          user: SpecSeed.user.id,
          location: SpecSeed.other_location.id
        )
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('network is not available in selected location')
    end

    it 'allows admin to create a user-owned address with location' do
      as(SpecSeed.admin) do
        json_post index_path, ip_address: payload.merge(
          user: SpecSeed.user.id,
          location: SpecSeed.location.id
        )
      end

      expect_status(200)
      expect(json['status']).to be(true)
      record = IpAddress.find_by!(ip_addr: payload[:addr])
      expect(record.user_id).to eq(SpecSeed.user.id)
    end
  end

  describe 'Update' do
    let!(:ip_to_update) { create_ip!(addr: '192.0.2.120', network: SpecSeed.network_v4) }

    it 'rejects unauthenticated access' do
      json_put show_path(ip_to_update.id), ip_address: { user: SpecSeed.user.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(ip_to_update.id), ip_address: { user: SpecSeed.user.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put show_path(ip_to_update.id), ip_address: { user: SpecSeed.user.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'requires environment when user is provided' do
      as(SpecSeed.admin) { json_put show_path(ip_to_update.id), ip_address: { user: SpecSeed.user.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('choose environment')
    end

    it 'rejects invalid environment for the address' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) do
        json_put show_path(ip_to_update.id), ip_address: {
          user: SpecSeed.user.id,
          environment: SpecSeed.other_environment.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('not available in environment')
    end

    it 'allows admin to change ownership' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) do
        json_put show_path(ip_to_update.id), ip_address: {
          user: SpecSeed.user.id,
          environment: SpecSeed.environment.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ip_to_update.reload.user_id).to eq(SpecSeed.user.id)
    end

    it 'prevents chown when the address belongs to a VPS in IP ownership env' do
      SpecSeed.environment.update!(user_ip_ownership: true)
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps')
      user_netif = create_netif!(vps: user_vps)
      ip_assigned = create_ip!(addr: '192.0.2.121', network: SpecSeed.network_v4, netif: user_netif)

      as(SpecSeed.admin) do
        json_put show_path(ip_assigned.id), ip_address: {
          user: SpecSeed.other_user.id,
          environment: SpecSeed.environment.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('cannot chown IP while it belongs to a VPS')
    end
  end

  describe 'Assign' do
    let(:assign_data) do
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps')
      user_netif = create_netif!(vps: user_vps)
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'other-vps')
      other_netif = create_netif!(vps: other_vps)
      {
        user_netif: user_netif,
        other_netif: other_netif,
        ip_free: create_ip!(addr: '192.0.2.30', network: SpecSeed.network_v4),
        ip_owned_other: create_ip!(addr: '192.0.2.31', network: SpecSeed.network_v4, user: SpecSeed.other_user),
        ip_routed_other: create_ip!(addr: '192.0.2.32', network: SpecSeed.network_v4, netif: other_netif)
      }
    end

    it 'rejects unauthenticated access' do
      data = assign_data
      json_post assign_path(data[:ip_free].id), ip_address: { network_interface: data[:user_netif].id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to assign free addresses to their interface' do
      ensure_signer_unlocked!
      starting_transactions = Transaction.count

      expect do
        data = assign_data
        as(SpecSeed.user) do
          json_post assign_path(data[:ip_free].id), ip_address: { network_interface: data[:user_netif].id }
        end
      end.to change(TransactionChain, :count).by(1)

      expect(Transaction.count).to be >= starting_transactions + 1
      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'denies assigning addresses owned by another user' do
      data = assign_data
      as(SpecSeed.user) do
        json_post assign_path(data[:ip_owned_other].id), ip_address: { network_interface: data[:user_netif].id }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'denies assigning addresses routed to another user interface' do
      data = assign_data
      as(SpecSeed.user) do
        json_post assign_path(data[:ip_routed_other].id), ip_address: { network_interface: data[:other_netif].id }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end
  end

  describe 'AssignWithHostAddress' do
    let!(:user_vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps') }
    let!(:user_netif) { create_netif!(vps: user_vps) }
    let!(:ip_free) { create_ip!(addr: '192.0.2.40', network: SpecSeed.network_v4) }

    it 'rejects unauthenticated access' do
      json_post assign_with_host_path(ip_free.id), ip_address: { network_interface: user_netif.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to assign with host address' do
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.user) do
          json_post assign_with_host_path(ip_free.id), ip_address: { network_interface: user_netif.id }
        end
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'rejects invalid host address' do
      ip_other = create_ip!(addr: '192.0.2.41', network: SpecSeed.network_v4)

      as(SpecSeed.user) do
        json_post assign_with_host_path(ip_free.id), ip_address: {
          network_interface: user_netif.id,
          host_ip_address: ip_other.host_ip_addresses.first.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('invalid host IP address')
    end
  end

  describe 'Free' do
    let(:free_data) do
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps')
      user_netif = create_netif!(vps: user_vps)
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'other-vps')
      other_netif = create_netif!(vps: other_vps)
      {
        ip_assigned_to_user: create_ip!(addr: '192.0.2.50', network: SpecSeed.network_v4, netif: user_netif),
        ip_assigned_to_other: create_ip!(addr: '192.0.2.51', network: SpecSeed.network_v4, netif: other_netif),
        ip_free: create_ip!(addr: '192.0.2.52', network: SpecSeed.network_v4)
      }
    end

    it 'rejects unauthenticated access' do
      json_post free_path(free_data[:ip_assigned_to_user].id), {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to free their routed address' do
      ensure_signer_unlocked!
      allocate_ip_resource!(user: SpecSeed.user, environment: SpecSeed.environment)

      as(SpecSeed.user) { json_post free_path(free_data[:ip_assigned_to_user].id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
      state_id = response_action_state_id
      expect(state_id).not_to be_nil
      expect(state_id.to_i).to be > 0
    end

    it 'denies freeing addresses routed to another user' do
      as(SpecSeed.user) { json_post free_path(free_data[:ip_assigned_to_other].id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'rejects freeing unassigned addresses' do
      as(SpecSeed.user) { json_post free_path(free_data[:ip_free].id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('not assigned')
    end

    it 'allows admins to free other users addresses' do
      ensure_signer_unlocked!
      allocate_ip_resource!(user: SpecSeed.other_user, environment: SpecSeed.environment)

      as(SpecSeed.admin) { json_post free_path(free_data[:ip_assigned_to_other].id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
      state_id = response_action_state_id
      expect(state_id).not_to be_nil
      expect(state_id.to_i).to be > 0
    end
  end
end
