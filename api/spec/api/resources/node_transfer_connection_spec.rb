# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::NodeTransferConnection' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.node
    SpecSeed.other_node
  end

  def index_path
    vpath('/node_transfer_connections')
  end

  def show_path(id)
    vpath("/node_transfer_connections/#{id}")
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
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
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

  def connection_obj
    json.dig('response', 'node_transfer_connection') || json['response']
  end

  def connection_list
    json.dig('response', 'node_transfer_connections') || []
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_connection!(**attrs)
    NodeTransferConnection.create!(
      {
        node_a: SpecSeed.node,
        node_b: SpecSeed.other_node,
        node_a_ip_addr: '10.0.0.15',
        node_b_ip_addr: '10.0.0.16',
        enabled: true
      }.merge(attrs)
    )
  end

  def third_node
    Node.find_by(name: 'spec-node-c') || Node.create!(
      name: 'spec-node-c',
      location: SpecSeed.location,
      role: :node,
      hypervisor_type: :vpsadminos,
      ip_addr: '192.0.2.103',
      max_vps: 10,
      cpus: 4,
      total_memory: 4096,
      total_swap: 1024,
      active: true
    )
  end

  describe 'API description' do
    it 'includes node_transfer_connection endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'node_transfer_connection#index',
        'node_transfer_connection#show',
        'node_transfer_connection#create',
        'node_transfer_connection#update',
        'node_transfer_connection#delete'
      )
    end

    it 'does not expose node pair changes in update input' do
      update_params = action_input_params('node_transfer_connection', 'update')

      expect(update_params.keys).to include('node_a_ip_addr', 'node_b_ip_addr', 'enabled')
      expect(update_params.keys).not_to include('node_a', 'node_b')
    end
  end

  describe 'Create' do
    let(:payload) do
      {
        node_a: SpecSeed.node.id,
        node_b: SpecSeed.other_node.id,
        node_a_ip_addr: '10.0.0.15',
        node_b_ip_addr: '10.0.0.16'
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, node_transfer_connection: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, node_transfer_connection: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, node_transfer_connection: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a node transfer connection' do
      expect do
        as(SpecSeed.admin) { json_post index_path, node_transfer_connection: payload }
      end.to change(NodeTransferConnection, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      obj = connection_obj
      expect(rid(obj['node_a'])).to eq(SpecSeed.node.id)
      expect(rid(obj['node_b'])).to eq(SpecSeed.other_node.id)
      expect(obj['node_a_ip_addr']).to eq('10.0.0.15')
      expect(obj['node_b_ip_addr']).to eq('10.0.0.16')
      expect(obj['enabled']).to be(true)
    end

    it 'normalizes reversed node order on create' do
      as(SpecSeed.admin) do
        json_post index_path, node_transfer_connection: {
          node_a: SpecSeed.other_node.id,
          node_b: SpecSeed.node.id,
          node_a_ip_addr: '10.0.0.16',
          node_b_ip_addr: '10.0.0.15'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      obj = connection_obj
      expect(rid(obj['node_a'])).to eq(SpecSeed.node.id)
      expect(rid(obj['node_b'])).to eq(SpecSeed.other_node.id)
      expect(obj['node_a_ip_addr']).to eq('10.0.0.15')
      expect(obj['node_b_ip_addr']).to eq('10.0.0.16')
      expect(obj['enabled']).to be(true)
    end

    it 'rejects duplicate pairs even when reversed' do
      create_connection!

      expect do
        as(SpecSeed.admin) do
          json_post index_path, node_transfer_connection: {
            node_a: SpecSeed.other_node.id,
            node_b: SpecSeed.node.id,
            node_a_ip_addr: '10.0.0.16',
            node_b_ip_addr: '10.0.0.15'
          }
        end
      end.not_to change(NodeTransferConnection, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors).not_to be_empty
    end

    it 'rejects same-node pairs' do
      as(SpecSeed.admin) do
        json_post index_path, node_transfer_connection: payload.merge(
          node_b: SpecSeed.node.id
        )
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('node_b')
    end

    it 'rejects CIDR input' do
      as(SpecSeed.admin) do
        json_post index_path, node_transfer_connection: payload.merge(
          node_a_ip_addr: '10.0.0.15/24'
        )
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('node_a_ip_addr')
    end

    it 'rejects invalid IP input' do
      as(SpecSeed.admin) do
        json_post index_path, node_transfer_connection: payload.merge(
          node_a_ip_addr: 'not-an-ip'
        )
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('node_a_ip_addr')
    end

    it 'defaults enabled to true when omitted' do
      as(SpecSeed.admin) { json_post index_path, node_transfer_connection: payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(connection_obj['enabled']).to be(true)
      expect(NodeTransferConnection.last.enabled).to be(true)
    end
  end

  describe 'Index and Show' do
    let!(:enabled_conn) { create_connection! }
    let!(:disabled_conn) do
      create_connection!(
        node_a: SpecSeed.other_node,
        node_b: third_node,
        node_a_ip_addr: '10.0.0.17',
        node_b_ip_addr: '10.0.0.18',
        enabled: false
      )
    end

    it 'allows admin to list connections' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(connection_list.map { |row| row['id'] }).to include(enabled_conn.id, disabled_conn.id)
    end

    it 'filters by node regardless of canonical ordering' do
      as(SpecSeed.admin) do
        json_get index_path, node_transfer_connection: { node: SpecSeed.other_node.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(connection_list.map { |row| row['id'] }).to include(enabled_conn.id, disabled_conn.id)

      as(SpecSeed.admin) do
        json_get index_path, node_transfer_connection: { node: third_node.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(connection_list.map { |row| row['id'] }).to eq([disabled_conn.id])
    end

    it 'filters by enabled' do
      as(SpecSeed.admin) do
        json_get index_path, node_transfer_connection: { enabled: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(connection_list.map { |row| row['id'] }).to eq([disabled_conn.id])
    end

    it 'shows a single connection' do
      as(SpecSeed.admin) { json_get show_path(enabled_conn.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(connection_obj['id']).to eq(enabled_conn.id)
      expect(rid(connection_obj['node_a'])).to eq(enabled_conn.node_a_id)
      expect(rid(connection_obj['node_b'])).to eq(enabled_conn.node_b_id)
    end
  end

  describe 'Update' do
    let!(:conn) { create_connection! }

    it 'allows admin to update endpoint addresses' do
      as(SpecSeed.admin) do
        json_put show_path(conn.id), node_transfer_connection: {
          node_a_ip_addr: '10.0.1.15',
          node_b_ip_addr: '10.0.1.16'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(connection_obj['node_a_ip_addr']).to eq('10.0.1.15')
      expect(connection_obj['node_b_ip_addr']).to eq('10.0.1.16')
      expect(conn.reload.node_a_ip_addr).to eq('10.0.1.15')
      expect(conn.node_b_ip_addr).to eq('10.0.1.16')
    end

    it 'allows admin to toggle enabled' do
      as(SpecSeed.admin) do
        json_put show_path(conn.id), node_transfer_connection: { enabled: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(connection_obj['enabled']).to be(false)
      expect(conn.reload.enabled).to be(false)
    end

    it 'rejects invalid IP updates' do
      as(SpecSeed.admin) do
        json_put show_path(conn.id), node_transfer_connection: {
          node_a_ip_addr: '10.0.1.15/24'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('node_a_ip_addr')
    end
  end

  describe 'Delete' do
    it 'allows admin to delete a connection' do
      conn = create_connection!

      expect do
        as(SpecSeed.admin) { json_delete show_path(conn.id) }
      end.to change(NodeTransferConnection, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(NodeTransferConnection.find_by(id: conn.id)).to be_nil
    end
  end
end
