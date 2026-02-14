# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::NetworkInterfaceMonitor' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.location
    SpecSeed.other_location
    SpecSeed.environment
    SpecSeed.other_environment
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  let!(:fixtures) do
    t1 = Time.utc(2025, 1, 1, 12, 0, 0)
    t2 = Time.utc(2025, 1, 2, 12, 0, 0)
    t3 = Time.utc(2025, 1, 3, 12, 0, 0)

    vps_user = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-netifmon-user')
    vps_other = create_vps!(user: SpecSeed.other_user, node: SpecSeed.other_node, hostname: 'spec-netifmon-other')

    netif_u1 = create_netif!(vps: vps_user, name: 'eth0')
    netif_u2 = create_netif!(vps: vps_user, name: 'eth1')
    netif_o1 = create_netif!(vps: vps_other, name: 'eth0')

    mon_u1 = create_monitor!(
      netif: netif_u1,
      bytes: 1000,
      bytes_in: 600,
      bytes_out: 400,
      packets: 100,
      packets_in: 60,
      packets_out: 40,
      delta: 60,
      updated_at: t1
    )

    mon_u2 = create_monitor!(
      netif: netif_u2,
      bytes: 500,
      bytes_in: 200,
      bytes_out: 300,
      packets: 50,
      packets_in: 20,
      packets_out: 30,
      delta: 30,
      updated_at: t2
    )

    mon_o1 = create_monitor!(
      netif: netif_o1,
      bytes: 2000,
      bytes_in: 1000,
      bytes_out: 1000,
      packets: 200,
      packets_in: 120,
      packets_out: 80,
      delta: 80,
      updated_at: t3
    )

    {
      vps_user: vps_user,
      vps_other: vps_other,
      netif_u1: netif_u1,
      netif_u2: netif_u2,
      netif_o1: netif_o1,
      mon_u1: mon_u1,
      mon_u2: mon_u2,
      mon_o1: mon_o1
    }
  end

  def vps_user
    fixtures.fetch(:vps_user)
  end

  def vps_other
    fixtures.fetch(:vps_other)
  end

  def netif_u1
    fixtures.fetch(:netif_u1)
  end

  def netif_u2
    fixtures.fetch(:netif_u2)
  end

  def netif_o1
    fixtures.fetch(:netif_o1)
  end

  def mon_u1
    fixtures.fetch(:mon_u1)
  end

  def mon_u2
    fixtures.fetch(:mon_u2)
  end

  def mon_o1
    fixtures.fetch(:mon_o1)
  end

  def index_path
    vpath('/network_interface_monitors')
  end

  def show_path(id)
    vpath("/network_interface_monitors/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def monitors
    json.dig('response', 'network_interface_monitors') || []
  end

  def monitor_obj
    json.dig('response', 'network_interface_monitor') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
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

  def create_netif!(vps:, name:)
    NetworkInterface.create!(
      vps: vps,
      name: name,
      kind: :veth_routed
    )
  end

  def create_monitor!(netif:, bytes:, bytes_in:, bytes_out:, packets:, packets_in:, packets_out:, delta:,
                      updated_at: Time.now)
    NetworkInterfaceMonitor.create!(
      network_interface_id: netif.id,
      bytes: bytes,
      bytes_in: bytes_in,
      bytes_out: bytes_out,
      packets: packets,
      packets_in: packets_in,
      packets_out: packets_out,
      delta: delta,
      bytes_in_readout: bytes_in,
      bytes_out_readout: bytes_out,
      packets_in_readout: packets_in,
      packets_out_readout: packets_out,
      updated_at: updated_at,
      created_at: updated_at
    )
  end

  describe 'API description' do
    it 'includes network interface monitor scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('network_interface_monitor#index', 'network_interface_monitor#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only user monitors for non-admins' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = monitors.map { |row| row['id'] }
      expect(ids).to contain_exactly(netif_u1.id, netif_u2.id)
      expect(ids).not_to include(netif_o1.id)

      row = monitors.detect { |item| item['id'] == netif_u1.id }
      expected_keys = %w[id network_interface bytes bytes_in bytes_out packets packets_in packets_out delta updated_at]
      expect(row.keys).to include(*expected_keys)
      expect(resource_id(row['network_interface'])).to eq(netif_u1.id)
      expect(row['network_interface']['name']).to eq(netif_u1.name)
    end

    it 'ignores user filter for non-admins' do
      as(SpecSeed.user) do
        json_get index_path, network_interface_monitor: { user: SpecSeed.other_user.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      ids = monitors.map { |row| row['id'] }
      expect(ids).to contain_exactly(netif_u1.id, netif_u2.id)
      expect(ids).not_to include(netif_o1.id)
    end

    it 'lists all monitors for admins' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = monitors.map { |row| row['id'] }
      expect(ids).to contain_exactly(netif_u1.id, netif_u2.id, netif_o1.id)
    end

    it 'filters by user for admins' do
      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { user: SpecSeed.user.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to contain_exactly(netif_u1.id, netif_u2.id)

      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { user: SpecSeed.other_user.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to contain_exactly(netif_o1.id)
    end

    it 'filters by environment, location, node, vps, and network_interface for admins' do
      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { environment: SpecSeed.environment.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to contain_exactly(netif_u1.id, netif_u2.id)

      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { environment: SpecSeed.other_environment.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to contain_exactly(netif_o1.id)

      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { location: SpecSeed.location.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to contain_exactly(netif_u1.id, netif_u2.id)

      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { node: SpecSeed.other_node.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to contain_exactly(netif_o1.id)

      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { vps: vps_user.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to contain_exactly(netif_u1.id, netif_u2.id)

      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { network_interface: netif_u1.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to contain_exactly(netif_u1.id)
    end

    it 'returns empty results for non-admin environment mismatch' do
      as(SpecSeed.user) do
        json_get index_path, network_interface_monitor: { environment: SpecSeed.other_environment.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors).to be_empty
    end

    it 'orders by bytes descending by default' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to eq([netif_o1.id, netif_u1.id, netif_u2.id])
    end

    it 'orders by bytes ascending' do
      as(SpecSeed.admin) { json_get index_path, network_interface_monitor: { order: 'bytes' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to eq([netif_u2.id, netif_u1.id, netif_o1.id])
    end

    it 'orders by packets descending' do
      as(SpecSeed.admin) { json_get index_path, network_interface_monitor: { order: '-packets' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.map { |row| row['id'] }).to eq([netif_o1.id, netif_u1.id, netif_u2.id])
    end

    it 'returns error on invalid order' do
      as(SpecSeed.admin) { json_get index_path, network_interface_monitor: { order: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to eq('invalid order')
    end

    it 'paginates with limit and from_id' do
      as(SpecSeed.admin) { json_get index_path, network_interface_monitor: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitors.size).to eq(1)

      as(SpecSeed.admin) do
        json_get index_path, network_interface_monitor: { order: 'id', from_id: netif_u1.id, limit: 25 }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      ids = monitors.map { |row| row['id'] }
      expect(ids).to all(be > netif_u1.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(netif_u1.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their monitor' do
      as(SpecSeed.user) { json_get show_path(netif_u1.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitor_obj['id']).to eq(netif_u1.id)
      expect(monitor_obj['bytes']).to eq(mon_u1.bytes)
      expect(monitor_obj['bytes_in']).to eq(mon_u1.bytes_in)
      expect(monitor_obj['bytes_out']).to eq(mon_u1.bytes_out)
      expect(monitor_obj['packets']).to eq(mon_u1.packets)
      expect(monitor_obj['packets_in']).to eq(mon_u1.packets_in)
      expect(monitor_obj['packets_out']).to eq(mon_u1.packets_out)
      expect(monitor_obj['delta']).to eq(mon_u1.delta)
      expect(monitor_obj['network_interface']['id']).to eq(netif_u1.id)
    end

    it 'prevents users from showing other monitors' do
      as(SpecSeed.user) { json_get show_path(netif_o1.id) }

      expect_status(404)
      expect(json['status']).to be(false)
      expect(response_message.to_s).to match(/object not found/i)
    end

    it 'allows admins to show any monitor' do
      as(SpecSeed.admin) { json_get show_path(netif_o1.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(monitor_obj['id']).to eq(netif_o1.id)
    end

    it 'returns 404 for unknown id' do
      missing = NetworkInterface.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
      expect(response_message.to_s).to match(/object not found/i)
    end
  end
end
