# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Node' do
  let(:node) { Node.find(SpecSeed.node.id) }
  let(:other_node) { Node.find(SpecSeed.other_node.id) }

  before do
    header 'Accept', 'application/json'
    node
    other_node
  end

  def index_path
    vpath('/nodes')
  end

  def show_path(id)
    vpath("/nodes/#{id}")
  end

  def overview_list_path
    vpath('/nodes/overview_list')
  end

  def public_status_path
    vpath('/nodes/public_status')
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def nodes
    json.dig('response', 'nodes')
  end

  def node_obj
    json.dig('response', 'node')
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

    it 'allows users to list nodes with limited output' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(nodes).to be_an(Array)

      ids = nodes.map { |row| row['id'] }
      expect(ids).to include(node.id, other_node.id)

      row = nodes.find { |item| item['id'] == node.id }
      expect(row).to include('id', 'name', 'domain_name', 'fqdn', 'location')
      expect(row['name']).to eq(node.name)
      expect(row['domain_name']).to eq(node.domain_name)
      expect(row['fqdn']).to eq(node.fqdn)
      expect(resource_id(row['location'])).to eq(node.location_id)
      expect(row['hypervisor_type']).to eq(node.hypervisor_type)
      expect(row).not_to have_key('ip_addr')
      expect(row).not_to have_key('max_vps')
      expect(row).not_to have_key('type')
    end

    it 'allows support to list nodes with limited output' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      row = nodes.find { |item| item['id'] == node.id }
      expect(row).not_to have_key('ip_addr')
      expect(row).not_to have_key('max_vps')
    end

    it 'allows admins to list nodes with full output' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      row = nodes.find { |item| item['id'] == node.id }
      expect(row['ip_addr']).to eq(node.ip_addr)
      expect(row['cpus']).to eq(node.cpus)
      expect(row['total_memory']).to eq(node.total_memory)
      expect(row['type']).to eq(node.role)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, node: { limit: 1 } }

      expect_status(200)
      expect(nodes.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = Node.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, node: { from_id: boundary } }

      expect_status(200)
      ids = nodes.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Node.count)
    end

    it 'filters by location' do
      as(SpecSeed.admin) { json_get index_path, node: { location: node.location_id } }

      expect_status(200)
      ids = nodes.map { |row| row['id'] }
      expect(ids).to include(node.id)
      expect(ids).not_to include(other_node.id)
    end

    it 'filters by environment' do
      as(SpecSeed.admin) { json_get index_path, node: { environment: node.location.environment_id } }

      expect_status(200)
      ids = nodes.map { |row| row['id'] }
      expect(ids).to include(node.id)
      expect(ids).not_to include(other_node.id)
    end

    it 'filters by state' do
      Node.where(id: other_node.id).update_all(active: false)

      as(SpecSeed.admin) { json_get index_path, node: { state: 'inactive' } }

      expect_status(200)
      ids = nodes.map { |row| row['id'] }
      expect(ids).to include(other_node.id)
      expect(ids).not_to include(node.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(node.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show nodes with limited output' do
      as(SpecSeed.user) { json_get show_path(node.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(node_obj['id']).to eq(node.id)
      expect(node_obj['name']).to eq(node.name)
      expect(node_obj['domain_name']).to eq(node.domain_name)
      expect(node_obj['fqdn']).to eq(node.fqdn)
      expect(resource_id(node_obj['location'])).to eq(node.location_id)
      expect(node_obj['hypervisor_type']).to eq(node.hypervisor_type)
      expect(node_obj).not_to have_key('ip_addr')
      expect(node_obj).not_to have_key('max_vps')
    end

    it 'allows support to show nodes with limited output' do
      as(SpecSeed.support) { json_get show_path(node.id) }

      expect_status(200)
      expect(node_obj).not_to have_key('ip_addr')
      expect(node_obj).not_to have_key('max_vps')
    end

    it 'allows admins to show nodes with full output' do
      as(SpecSeed.admin) { json_get show_path(node.id) }

      expect_status(200)
      expect(node_obj['id']).to eq(node.id)
      expect(node_obj['name']).to eq(node.name)
      expect(node_obj['ip_addr']).to eq(node.ip_addr)
      expect(node_obj['cpus']).to eq(node.cpus)
      expect(node_obj['total_memory']).to eq(node.total_memory)
      expect(node_obj['type']).to eq(node.role)
    end

    it 'returns 404 for unknown node' do
      missing = Node.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'OverviewList' do
    it 'rejects unauthenticated access' do
      json_get overview_list_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get overview_list_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get overview_list_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to list overview data' do
      as(SpecSeed.admin) { json_get overview_list_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(nodes).to be_an(Array)

      ids = nodes.map { |row| row['id'] }
      expect(ids).to include(node.id, other_node.id)

      row = nodes.find { |item| item['id'] == node.id }
      expect(row['vps_running']).to eq(0)
      expect(row['vps_total']).to eq(0)
      expect(row['vps_free']).to eq(node.max_vps)
    end
  end

  describe 'PublicStatus' do
    it 'allows unauthenticated access with ids hidden' do
      json_get public_status_path

      expect_status(200)
      expect(json['status']).to be(true)
      expect(nodes).to be_an(Array)

      row = nodes.find { |item| item['name'] == node.domain_name }
      expect(row).not_to have_key('id')
      expect(resource_id(row['location'])).to eq(node.location_id)
      expect(row['vps_count']).to eq(0)
      expect(row['vps_free']).to eq(node.max_vps)
    end

    it 'includes ids for authenticated users' do
      as(SpecSeed.user) { json_get public_status_path }

      expect_status(200)
      row = nodes.find { |item| item['name'] == node.domain_name }
      expect(row['id']).to eq(node.id)
    end
  end
end
