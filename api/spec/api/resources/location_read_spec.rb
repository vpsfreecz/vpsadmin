# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Location' do
  let(:location) { SpecSeed.location }
  let(:other_location) { SpecSeed.other_location }

  before do
    header 'Accept', 'application/json'
    location
    other_location
  end

  def index_path
    vpath('/locations')
  end

  def show_path(id)
    vpath("/locations/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def locations
    json.dig('response', 'locations')
  end

  def location_obj
    json.dig('response', 'location')
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

  def create_hypervisor_node!
    Node.create!(
      location: location,
      name: 'spec-location-node',
      role: :node,
      hypervisor_type: :vpsadminos,
      ip_addr: '192.0.2.101',
      max_vps: 10,
      cpus: 4,
      total_memory: 2048,
      total_swap: 1024,
      active: true
    )
  end

  describe 'Index' do
    before do
      create_hypervisor_node!
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'allows users to list locations with limited output' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(locations).to be_an(Array)

      ids = locations.map { |row| row['id'] }
      expect(ids).to include(location.id, other_location.id)

      row = locations.find { |item| item['id'] == location.id }
      expect(row).to include('id', 'label', 'description', 'environment')
      expect(row['label']).to eq(location.label)
      expect(resource_id(row['environment'])).to eq(location.environment_id)
      expect(row).not_to have_key('domain')
      expect(row).not_to have_key('has_ipv6')
    end

    it 'allows support to list locations with limited output' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      row = locations.find { |item| item['id'] == location.id }
      expect(row).not_to have_key('domain')
      expect(row).not_to have_key('has_ipv6')
    end

    it 'allows admins to list locations with full output' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      row = locations.find { |item| item['id'] == location.id }
      expect(row['domain']).to eq(location.domain)
      expect(row['has_ipv6']).to eq(location.has_ipv6)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, location: { limit: 1 } }

      expect_status(200)
      expect(locations.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = Location.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, location: { from_id: boundary } }

      expect_status(200)
      ids = locations.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Location.count)
    end

    it 'filters by environment' do
      as(SpecSeed.admin) { json_get index_path, location: { environment: location.environment_id } }

      expect_status(200)
      ids = locations.map { |row| row['id'] }
      expect(ids).to include(location.id)
      expect(ids).not_to include(other_location.id)
    end

    it 'filters by has_hypervisor' do
      as(SpecSeed.admin) { json_get index_path, location: { has_hypervisor: true } }

      expect_status(200)
      ids = locations.map { |row| row['id'] }
      expect(ids).to include(location.id)
      expect(ids).not_to include(other_location.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(location.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show locations with limited output' do
      as(SpecSeed.user) { json_get show_path(location.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(location_obj['id']).to eq(location.id)
      expect(location_obj['label']).to eq(location.label)
      expect(location_obj).to have_key('description')
      expect(resource_id(location_obj['environment'])).to eq(location.environment_id)
      expect(location_obj['domain']).to eq(location.domain)
      expect(location_obj['has_ipv6']).to eq(location.has_ipv6)
    end

    it 'allows support to show locations with limited output' do
      as(SpecSeed.support) { json_get show_path(location.id) }

      expect_status(200)
      expect(location_obj['domain']).to eq(location.domain)
      expect(location_obj['has_ipv6']).to eq(location.has_ipv6)
    end

    it 'allows admins to show locations with full output' do
      as(SpecSeed.admin) { json_get show_path(location.id) }

      expect_status(200)
      expect(location_obj['id']).to eq(location.id)
      expect(location_obj['label']).to eq(location.label)
      expect(location_obj['domain']).to eq(location.domain)
      expect(location_obj['has_ipv6']).to eq(location.has_ipv6)
    end

    it 'returns 404 for unknown location' do
      missing = Location.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
