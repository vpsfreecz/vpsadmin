# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Network write actions' do # rubocop:disable RSpec/DescribeClass
  let(:ipv4_network) { SpecSeed.network_v4 }
  let(:ipv6_network) { SpecSeed.network_v6 }

  before do
    header 'Accept', 'application/json'
    ipv4_network
    ipv6_network
  end

  def index_path
    vpath('/networks')
  end

  def show_path(id)
    vpath("/networks/#{id}")
  end

  def add_addresses_path(id)
    vpath("/networks/#{id}/add_addresses")
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

  def net_obj
    json.dig('response', 'network') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
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

  def minimal_network_payload(address:, prefix:, ip_version: 4, overrides: {})
    payload = {
      address:,
      prefix:,
      ip_version:,
      role: 'public_access',
      managed: true,
      split_prefix: ip_version == 4 ? 32 : 128,
      purpose: 'any'
    }
    payload.merge!(overrides)
    payload
  end

  def ensure_node_current_status(node = SpecSeed.node)
    NodeCurrentStatus.find_or_create_by!(node:) do |st|
      st.vpsadmin_version = 'test'
      st.kernel = 'test'
      st.update_count = 1
    end
  end

  def create_network!(address:, prefix:, managed: true, overrides: {})
    Network.create!({
      label: "Spec Net #{SecureRandom.hex(3)}",
      ip_version: 4,
      address:,
      prefix:,
      role: :public_access,
      managed:,
      split_access: :no_access,
      split_prefix: 32,
      purpose: :any,
      primary_location: SpecSeed.location
    }.merge(overrides))
  end

  describe 'API description' do
    it 'includes network write endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('network#create', 'network#update', 'network#add_addresses')
    end

    it 'documents network write inputs' do
      create_params = action_input_params('network', 'create')
      update_params = action_input_params('network', 'update')
      add_params = action_input_params('network', 'add_addresses')

      expect(create_params.keys).to include(
        'address',
        'prefix',
        'ip_version',
        'role',
        'managed',
        'split_prefix',
        'purpose',
        'add_ip_addresses'
      )
      expect(update_params.keys).to include('address', 'prefix', 'ip_version', 'role', 'managed', 'split_prefix', 'purpose')
      expect(add_params.keys).to include('count', 'user', 'environment')
    end
  end

  describe 'Create' do
    let(:payload) { minimal_network_payload(address: '198.51.100.0', prefix: 24) }

    it 'rejects unauthenticated access' do
      json_post index_path, network: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, network: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, network: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a network' do
      ensure_signer_unlocked!
      ensure_node_current_status

      expect do
        as(SpecSeed.admin) { json_post index_path, network: payload }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(net_obj).to be_a(Hash)
      expect(net_obj['address']).to eq(payload[:address])
      expect(net_obj['prefix']).to eq(payload[:prefix])
      expect(net_obj['ip_version']).to eq(payload[:ip_version])
      expect(net_obj['role']).to eq(payload[:role])
      expect(net_obj['managed']).to eq(payload[:managed])
      expect(net_obj['split_prefix']).to eq(payload[:split_prefix])
      expect(net_obj['purpose']).to eq(payload[:purpose])

      record = Network.find_by!(address: payload[:address], prefix: payload[:prefix])
      expect(record.ip_version).to eq(payload[:ip_version])
      expect(record.role).to eq(payload[:role])
      expect(record.managed).to eq(payload[:managed])
      expect(record.split_prefix).to eq(payload[:split_prefix])
      expect(record.purpose).to eq(payload[:purpose])
    end

    it 'returns validation errors for missing address' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_post index_path, network: payload.except(:address) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('address')
    end

    it 'returns validation errors for invalid ip_version' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_post index_path, network: payload.merge(ip_version: 5) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('ip_version')
    end

    it 'returns validation errors for duplicate network' do
      ensure_signer_unlocked!

      duplicate_payload = minimal_network_payload(
        address: ipv4_network.address,
        prefix: ipv4_network.prefix
      )
      as(SpecSeed.admin) { json_post index_path, network: duplicate_payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('address')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(ipv4_network.id), network: { label: 'Spec Net Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(ipv4_network.id), network: { label: 'Spec Net Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put show_path(ipv4_network.id), network: { label: 'Spec Net Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update network fields' do
      new_label = "Spec Net Updated #{SecureRandom.hex(3)}"
      new_role = 'private_access'

      as(SpecSeed.admin) do
        json_put show_path(ipv4_network.id), network: {
          label: new_label,
          role: new_role
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(net_obj).to be_a(Hash)
      expect(net_obj['label']).to eq(new_label)
      expect(net_obj['role']).to eq(new_role)

      ipv4_network.reload
      expect(ipv4_network.label).to eq(new_label)
      expect(ipv4_network.role).to eq(new_role)
    end

    it 'returns validation errors for invalid ip_version' do
      as(SpecSeed.admin) { json_put show_path(ipv4_network.id), network: { ip_version: 5 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('ip_version')
    end
  end

  describe 'AddAddresses' do
    let(:managed_net) { create_network!(address: '203.0.113.0', prefix: 24, managed: true) }
    let(:unmanaged_net) { create_network!(address: '203.0.113.128', prefix: 25, managed: false) }

    it 'rejects unauthenticated access' do
      json_post add_addresses_path(managed_net.id), network: { count: 2 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post add_addresses_path(managed_net.id), network: { count: 2 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post add_addresses_path(managed_net.id), network: { count: 2 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to add IP addresses' do
      expect do
        as(SpecSeed.admin) { json_post add_addresses_path(managed_net.id), network: { count: 3 } }
      end.to change(IpAddress, :count).by(3)

      expect_status(200)
      expect(json['status']).to be(true)
      count = json.dig('response', 'network', 'count') || json.dig('response', 'count') || json['count']
      expect(count).to eq(3)
      expect(managed_net.ip_addresses.count).to eq(3)
    end

    it 'returns validation errors for invalid count' do
      as(SpecSeed.admin) { json_post add_addresses_path(managed_net.id), network: { count: 0 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('count')
    end

    it 'rejects unmanaged networks' do
      as(SpecSeed.admin) { json_post add_addresses_path(unmanaged_net.id), network: { count: 1 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to eq('this action can be used only on managed networks')
    end
  end
end
