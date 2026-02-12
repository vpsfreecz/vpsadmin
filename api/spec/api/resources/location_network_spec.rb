# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::LocationNetwork' do
  let(:ipv4_network) { SpecSeed.network_v4 }
  let(:ipv6_network) { SpecSeed.network_v6 }

  let(:ipv4_location_network) { LocationNetwork.find_by!(location: loc_a, network: ipv4_network) }
  let(:ipv6_location_network) { LocationNetwork.find_by!(location: loc_b, network: ipv6_network) }

  before do
    header 'Accept', 'application/json'
    loc_a
    loc_b
    ipv4_network
    ipv6_network
    ipv4_location_network
    ipv6_location_network
  end

  def loc_a
    SpecSeed.location
  end

  def loc_b
    SpecSeed.other_location
  end

  def index_path
    vpath('/location_networks')
  end

  def show_path(id)
    vpath("/location_networks/#{id}")
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
    delete path, nil, { 'CONTENT_TYPE' => 'application/json' }
  end

  def nets
    json.dig('response', 'location_networks')
  end

  def net_obj
    json.dig('response', 'location_network') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
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

  describe 'API description' do
    it 'includes location_network endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'location_network#index',
        'location_network#show',
        'location_network#create',
        'location_network#update',
        'location_network#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list location networks' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(nets).to be_a(Array)

      ids = nets.map { |row| row['id'] }
      expect(ids).to include(ipv4_location_network.id, ipv6_location_network.id)

      row = nets.detect { |item| item['id'] == ipv4_location_network.id }
      expect(row).to include('id', 'location', 'network', 'primary', 'priority', 'autopick', 'userpick')
      expect(resource_id(row['location'])).to eq(ipv4_location_network.location_id)
      expect(resource_id(row['network'])).to eq(ipv4_location_network.network_id)
    end

    it 'filters by location' do
      as(SpecSeed.admin) { json_get index_path, location_network: { location: loc_a.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = nets.map { |row| row['id'] }
      expect(ids).to include(ipv4_location_network.id)
      expect(ids).not_to include(ipv6_location_network.id)
    end

    it 'filters by network' do
      as(SpecSeed.admin) { json_get index_path, location_network: { network: ipv6_network.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = nets.map { |row| row['id'] }
      expect(ids).to include(ipv6_location_network.id)
      expect(ids).not_to include(ipv4_location_network.id)
    end

    it 'orders by priority within location' do
      LocationNetwork.create!(
        location: loc_a,
        network: ipv6_network,
        priority: 5,
        autopick: true,
        userpick: true,
        primary: false
      )

      as(SpecSeed.admin) { json_get index_path, location_network: { location: loc_a.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      priorities = nets.map { |row| row['priority'] }
      expect(priorities).to eq([5, 10])
    end

    it 'supports pagination limit' do
      as(SpecSeed.admin) { json_get index_path, location_network: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(nets.length).to eq(1)
    end

    it 'supports pagination from_id' do
      boundary = LocationNetwork.order(:id).first.id

      as(SpecSeed.admin) { json_get index_path, location_network: { from_id: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(nets.map { |row| row['id'] }).to all(be > boundary)
    end

    it 'returns meta count' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(LocationNetwork.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(ipv4_location_network.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get show_path(ipv4_location_network.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show a location network' do
      as(SpecSeed.admin) { json_get show_path(ipv4_location_network.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(net_obj).to be_a(Hash)
      expect(net_obj['id']).to eq(ipv4_location_network.id)
      expect(resource_id(net_obj['location'])).to eq(ipv4_location_network.location_id)
      expect(resource_id(net_obj['network'])).to eq(ipv4_location_network.network_id)
      expect(net_obj['priority']).to eq(ipv4_location_network.priority)
      expect(net_obj['autopick']).to eq(ipv4_location_network.autopick)
      expect(net_obj['userpick']).to eq(ipv4_location_network.userpick)
    end

    it 'returns 404 for unknown id' do
      missing = LocationNetwork.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:payload) do
      {
        location: loc_a.id,
        network: ipv6_network.id,
        primary: false,
        priority: 20,
        autopick: false,
        userpick: false
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, location_network: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, location_network: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, location_network: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a location network' do
      expect do
        as(SpecSeed.admin) { json_post index_path, location_network: payload }
      end.to change(LocationNetwork, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(net_obj).to be_a(Hash)
      expect(resource_id(net_obj['location'])).to eq(loc_a.id)
      expect(resource_id(net_obj['network'])).to eq(ipv6_network.id)
      expect(net_obj['priority']).to eq(20)
      expect(net_obj['autopick']).to be(false)
      expect(net_obj['userpick']).to be(false)

      record = LocationNetwork.find_by!(location: loc_a, network: ipv6_network)
      expect(record.priority).to eq(20)
      expect(record.autopick).to be(false)
      expect(record.userpick).to be(false)
    end

    it 'returns a friendly error when duplicate is created' do
      as(SpecSeed.admin) do
        json_post index_path, location_network: { location: loc_a.id, network: ipv4_network.id }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg.to_s).to include('already exists')
    end

    it 'returns validation errors for missing location' do
      as(SpecSeed.admin) { json_post index_path, location_network: payload.except(:location) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('location')
    end

    it 'returns validation errors for missing network' do
      as(SpecSeed.admin) { json_post index_path, location_network: payload.except(:network) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('network')
    end
  end

  describe 'Update' do
    let(:payload) do
      {
        priority: 42,
        autopick: false,
        userpick: false
      }
    end

    it 'rejects unauthenticated access' do
      json_put show_path(ipv4_location_network.id), location_network: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(ipv4_location_network.id), location_network: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put show_path(ipv4_location_network.id), location_network: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update a location network' do
      as(SpecSeed.admin) { json_put show_path(ipv4_location_network.id), location_network: payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(net_obj).to be_a(Hash)
      expect(net_obj['id']).to eq(ipv4_location_network.id)
      expect(net_obj['priority']).to eq(42)
      expect(net_obj['autopick']).to be(false)
      expect(net_obj['userpick']).to be(false)

      ipv4_location_network.reload
      expect(ipv4_location_network.priority).to eq(42)
      expect(ipv4_location_network.autopick).to be(false)
      expect(ipv4_location_network.userpick).to be(false)
    end

    it 'toggles primary location on the network' do
      expect(ipv4_location_network.primary).to be(true)

      as(SpecSeed.admin) { json_put show_path(ipv4_location_network.id), location_network: { primary: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ipv4_network.reload.primary_location_id).to be_nil

      as(SpecSeed.admin) { json_put show_path(ipv4_location_network.id), location_network: { primary: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ipv4_network.reload.primary_location_id).to eq(loc_a.id)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(ipv4_location_network.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(ipv4_location_network.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_delete show_path(ipv4_location_network.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a location network' do
      ln = LocationNetwork.create!(
        location: loc_a,
        network: ipv6_network,
        priority: 99,
        autopick: true,
        userpick: true,
        primary: false
      )

      expect do
        as(SpecSeed.admin) { json_delete show_path(ln.id) }
      end.to change(LocationNetwork, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'clears network primary location when deleting a primary link' do
      expect(ipv4_location_network.primary).to be(true)

      as(SpecSeed.admin) { json_delete show_path(ipv4_location_network.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ipv4_network.reload.primary_location_id).to be_nil
    end
  end
end
