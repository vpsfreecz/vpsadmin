# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Network' do
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

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def nets
    json.dig('response', 'networks')
  end

  def net_obj
    json.dig('response', 'network')
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to list networks with limited output' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(nets).to be_an(Array)

      ids = nets.map { |row| row['id'] }
      expect(ids).to include(ipv4_network.id, ipv6_network.id)

      row = nets.find { |item| item['id'] == ipv4_network.id }
      expect(row).to include('id', 'address', 'prefix', 'ip_version', 'role', 'split_access', 'split_prefix', 'purpose')
      expect(row['address']).to eq(ipv4_network.address)
      expect(row['prefix']).to eq(ipv4_network.prefix)
      expect(row['ip_version']).to eq(ipv4_network.ip_version)
      expect(row['role']).to eq(ipv4_network.role)
      expect(row['split_access']).to eq(ipv4_network.split_access)
      expect(row['split_prefix']).to eq(ipv4_network.split_prefix)
      expect(row['purpose']).to eq(ipv4_network.purpose)
      expect(row).not_to have_key('label')
      expect(row).not_to have_key('managed')
      expect(row).not_to have_key('primary_location')
      expect(row).not_to have_key('size')
    end

    it 'allows support to list networks with limited output' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      row = nets.find { |item| item['id'] == ipv4_network.id }
      expect(row).not_to have_key('label')
      expect(row).not_to have_key('managed')
      expect(row).not_to have_key('primary_location')
    end

    it 'allows admins to list networks with full output' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      row = nets.find { |item| item['id'] == ipv4_network.id }
      expect(row['label']).to eq(ipv4_network.label)
      expect(row['managed']).to eq(ipv4_network.managed)
      expect(resource_id(row['primary_location'])).to eq(ipv4_network.primary_location_id)
      expect(row['size']).to eq(ipv4_network.size)
      expect(row['used']).to eq(ipv4_network.used)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, network: { limit: 1 } }

      expect_status(200)
      expect(nets.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = Network.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, network: { from_id: boundary } }

      expect_status(200)
      ids = nets.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Network.count)
    end

    it 'filters by location' do
      as(SpecSeed.admin) { json_get index_path, network: { location: SpecSeed.location.id } }

      expect_status(200)
      ids = nets.map { |row| row['id'] }
      expect(ids).to include(ipv4_network.id)
      expect(ids).not_to include(ipv6_network.id)
    end

    it 'filters by purpose' do
      as(SpecSeed.admin) { json_get index_path, network: { purpose: ipv6_network.purpose } }

      expect_status(200)
      ids = nets.map { |row| row['id'] }
      expect(ids).to include(ipv6_network.id)
      expect(ids).not_to include(ipv4_network.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(ipv4_network.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show networks with limited output' do
      as(SpecSeed.user) { json_get show_path(ipv4_network.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(net_obj['id']).to eq(ipv4_network.id)
      expect(net_obj['address']).to eq(ipv4_network.address)
      expect(net_obj['prefix']).to eq(ipv4_network.prefix)
      expect(net_obj['ip_version']).to eq(ipv4_network.ip_version)
      expect(net_obj['role']).to eq(ipv4_network.role)
      expect(net_obj['split_access']).to eq(ipv4_network.split_access)
      expect(net_obj['split_prefix']).to eq(ipv4_network.split_prefix)
      expect(net_obj['purpose']).to eq(ipv4_network.purpose)
      expect(net_obj).not_to have_key('label')
      expect(net_obj).not_to have_key('managed')
      expect(net_obj).not_to have_key('primary_location')
      expect(net_obj).not_to have_key('size')
    end

    it 'allows support to show networks with limited output' do
      as(SpecSeed.support) { json_get show_path(ipv4_network.id) }

      expect_status(200)
      expect(net_obj).not_to have_key('label')
      expect(net_obj).not_to have_key('managed')
      expect(net_obj).not_to have_key('primary_location')
    end

    it 'allows admins to show networks with full output' do
      as(SpecSeed.admin) { json_get show_path(ipv4_network.id) }

      expect_status(200)
      expect(net_obj['id']).to eq(ipv4_network.id)
      expect(net_obj['label']).to eq(ipv4_network.label)
      expect(net_obj['managed']).to eq(ipv4_network.managed)
      expect(resource_id(net_obj['primary_location'])).to eq(ipv4_network.primary_location_id)
      expect(net_obj['size']).to eq(ipv4_network.size)
      expect(net_obj['used']).to eq(ipv4_network.used)
    end

    it 'returns 404 for unknown network' do
      missing = Network.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
