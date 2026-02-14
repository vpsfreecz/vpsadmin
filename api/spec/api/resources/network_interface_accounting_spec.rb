# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::NetworkInterfaceAccounting' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
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

  def user
    SpecSeed.user
  end

  def other_user
    SpecSeed.other_user
  end

  def admin
    SpecSeed.admin
  end

  let!(:fixtures) do
    vps_u_a = create_vps!(user: user, node: SpecSeed.node, hostname: 'spec-netacc-u-a')
    vps_u_b = create_vps!(user: user, node: SpecSeed.other_node, hostname: 'spec-netacc-u-b')
    vps_o_a = create_vps!(user: other_user, node: SpecSeed.node, hostname: 'spec-netacc-o-a')

    netif_u_a0 = create_netif!(vps: vps_u_a, name: 'eth0')
    netif_u_a1 = create_netif!(vps: vps_u_a, name: 'eth1')
    netif_u_b0 = create_netif!(vps: vps_u_b, name: 'eth0')
    netif_o_a0 = create_netif!(vps: vps_o_a, name: 'eth0')

    t1 = Time.utc(2025, 1, 8, 12, 0, 0)
    t2 = Time.utc(2025, 1, 9, 12, 0, 0)
    t3 = Time.utc(2025, 1, 10, 12, 0, 0)
    t4 = Time.utc(2025, 1, 11, 12, 0, 0)
    t5 = Time.utc(2025, 2, 1, 12, 0, 0)

    acc_u_a0_jan = create_monthly!(
      netif: netif_u_a0,
      user: user,
      year: 2025,
      month: 1,
      bytes_in: 100,
      bytes_out: 50,
      packets_in: 10,
      packets_out: 5,
      created_at: t3,
      updated_at: t4
    )

    acc_u_a1_jan = create_monthly!(
      netif: netif_u_a1,
      user: user,
      year: 2025,
      month: 1,
      bytes_in: 300,
      bytes_out: 100,
      packets_in: 30,
      packets_out: 10,
      created_at: t2,
      updated_at: t4 + 60
    )

    acc_u_b0_jan = create_monthly!(
      netif: netif_u_b0,
      user: user,
      year: 2025,
      month: 1,
      bytes_in: 10,
      bytes_out: 0,
      packets_in: 1,
      packets_out: 0,
      created_at: t1,
      updated_at: t1
    )

    acc_u_a0_feb = create_monthly!(
      netif: netif_u_a0,
      user: user,
      year: 2025,
      month: 2,
      bytes_in: 5,
      bytes_out: 5,
      packets_in: 1,
      packets_out: 1,
      created_at: t5,
      updated_at: t5
    )

    acc_o_a0_jan = create_monthly!(
      netif: netif_o_a0,
      user: other_user,
      year: 2025,
      month: 1,
      bytes_in: 50,
      bytes_out: 0,
      packets_in: 5,
      packets_out: 0,
      created_at: t2,
      updated_at: t2
    )

    {
      vps_u_a: vps_u_a,
      t3: t3,
      t4: t4,
      acc_u_a0_jan: acc_u_a0_jan,
      acc_u_a1_jan: acc_u_a1_jan,
      acc_u_b0_jan: acc_u_b0_jan,
      acc_u_a0_feb: acc_u_a0_feb,
      acc_o_a0_jan: acc_o_a0_jan
    }
  end

  def vps_u_a
    fixtures.fetch(:vps_u_a)
  end

  def acc_u_a0_jan
    fixtures.fetch(:acc_u_a0_jan)
  end

  def acc_u_a1_jan
    fixtures.fetch(:acc_u_a1_jan)
  end

  def acc_u_b0_jan
    fixtures.fetch(:acc_u_b0_jan)
  end

  def acc_u_a0_feb
    fixtures.fetch(:acc_u_a0_feb)
  end

  def acc_o_a0_jan
    fixtures.fetch(:acc_o_a0_jan)
  end

  def t3
    fixtures.fetch(:t3)
  end

  def t4
    fixtures.fetch(:t4)
  end

  def index_path
    vpath('/network_interface_accountings')
  end

  def user_top_path
    vpath('/network_interface_accountings/user_top')
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def accountings
    json.dig('response', 'network_interface_accountings')
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
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

  def create_monthly!(netif:, user:, year:, month:, bytes_in:, bytes_out:, packets_in: 0, packets_out: 0,
                      created_at: nil, updated_at: nil)
    NetworkInterfaceMonthlyAccounting.create!(
      network_interface: netif,
      user: user,
      year: year,
      month: month,
      bytes_in: bytes_in,
      bytes_out: bytes_out,
      packets_in: packets_in,
      packets_out: packets_out,
      created_at: created_at,
      updated_at: updated_at
    )
  end

  def row_key(row)
    [resource_id(row['network_interface']), row['year'], row['month']]
  end

  def record_key(record)
    [record.network_interface_id, record.year, record.month]
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'restricts normal users to their VPSes' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      rows = accountings
      keys = rows.map { |row| row_key(row) }

      expect(keys).to include(
        record_key(acc_u_a0_jan),
        record_key(acc_u_a1_jan),
        record_key(acc_u_b0_jan),
        record_key(acc_u_a0_feb)
      )
      expect(keys).not_to include(record_key(acc_o_a0_jan))

      row = rows.detect { |item| row_key(item) == record_key(acc_u_a0_jan) }
      expected_keys = %w[
        network_interface bytes bytes_in bytes_out packets packets_in packets_out year month created_at updated_at
      ]
      expect(row.keys).to include(*expected_keys)
      expect(row['bytes']).to eq(row['bytes_in'] + row['bytes_out'])
      expect(row['packets']).to eq(row['packets_in'] + row['packets_out'])
    end

    it 'allows admins to list all records' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(
        record_key(acc_u_a0_jan),
        record_key(acc_u_a1_jan),
        record_key(acc_u_b0_jan),
        record_key(acc_u_a0_feb),
        record_key(acc_o_a0_jan)
      )
    end

    it 'ignores user filter for non-admins' do
      as(user) { json_get index_path, network_interface_accounting: { user: other_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to include(
        record_key(acc_u_a0_jan),
        record_key(acc_u_a1_jan),
        record_key(acc_u_b0_jan),
        record_key(acc_u_a0_feb)
      )
      expect(keys).not_to include(record_key(acc_o_a0_jan))
    end

    it 'filters by user for admins' do
      as(admin) { json_get index_path, network_interface_accounting: { user: other_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(record_key(acc_o_a0_jan))
    end

    it 'filters by year and month' do
      as(admin) { json_get index_path, network_interface_accounting: { year: 2025, month: 2 } }

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(record_key(acc_u_a0_feb))
    end

    it 'filters by vps' do
      as(user) { json_get index_path, network_interface_accounting: { vps: vps_u_a.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(
        record_key(acc_u_a0_jan),
        record_key(acc_u_a1_jan),
        record_key(acc_u_a0_feb)
      )
    end

    it 'filters by node' do
      as(user) { json_get index_path, network_interface_accounting: { node: SpecSeed.other_node.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(record_key(acc_u_b0_jan))
    end

    it 'filters by location' do
      as(user) { json_get index_path, network_interface_accounting: { location: SpecSeed.location.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(
        record_key(acc_u_a0_jan),
        record_key(acc_u_a1_jan),
        record_key(acc_u_a0_feb)
      )
    end

    it 'filters by environment' do
      as(user) { json_get index_path, network_interface_accounting: { environment: SpecSeed.other_environment.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(record_key(acc_u_b0_jan))
    end

    it 'filters by created_at range' do
      as(admin) do
        json_get index_path, network_interface_accounting: {
          from: t3.iso8601,
          to: t4.iso8601
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(record_key(acc_u_a0_jan))
    end

    it 'orders by created_at desc by default' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      expect(row_key(accountings.first)).to eq(record_key(acc_u_a0_feb))
    end

    it 'orders by updated_at desc' do
      as(admin) { json_get index_path, network_interface_accounting: { order: 'updated_at' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(row_key(accountings.first)).to eq(record_key(acc_u_a0_feb))

      jan_rows = accountings.select { |row| row['year'] == 2025 && row['month'] == 1 }
      expect(row_key(jan_rows.first)).to eq(record_key(acc_u_a1_jan))
    end

    it 'orders by bytes descending with from_bytes pagination' do
      as(admin) { json_get index_path, network_interface_accounting: { order: 'descending' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(row_key(accountings.first)).to eq(record_key(acc_u_a1_jan))

      boundary = 400
      as(admin) { json_get index_path, network_interface_accounting: { order: 'descending', from_bytes: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(accountings.map { |row| row['bytes'] }).to all(be < boundary)
    end

    it 'orders by bytes ascending with from_bytes pagination' do
      as(admin) { json_get index_path, network_interface_accounting: { order: 'ascending' } }

      expect_status(200)
      expect(json['status']).to be(true)

      first_key = row_key(accountings.first)
      expect([record_key(acc_u_b0_jan), record_key(acc_u_a0_feb)]).to include(first_key)
      expect(accountings.first['bytes']).to eq(10)

      boundary = 10
      as(admin) { json_get index_path, network_interface_accounting: { order: 'ascending', from_bytes: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(accountings.map { |row| row['bytes'] }).to all(be > boundary)
    end

    it 'supports from_date pagination for created_at' do
      as(admin) do
        json_get index_path, network_interface_accounting: {
          order: 'created_at',
          from_date: t3.iso8601
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      keys = accountings.map { |row| row_key(row) }
      expect(keys).to contain_exactly(
        record_key(acc_u_a1_jan),
        record_key(acc_u_b0_jan),
        record_key(acc_o_a0_jan)
      )
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path, network_interface_accounting: { limit: 2 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(accountings.size).to eq(2)
    end

    it 'returns total_count in meta for admin and user' do
      as(admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(NetworkInterfaceMonthlyAccounting.count)

      as(user) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)

      expected_count = NetworkInterfaceMonthlyAccounting
                       .joins(network_interface: :vps)
                       .where(vpses: { user_id: user.id })
                       .count
      expect(json.dig('response', '_meta', 'total_count')).to eq(expected_count)
    end

    it 'validates order choices' do
      as(admin) { json_get index_path, network_interface_accounting: { order: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('order')
    end
  end

  describe 'UserTop' do
    it 'rejects unauthenticated access' do
      json_get user_top_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(user) { json_get user_top_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'aggregates traffic per user for admins' do
      as(admin) { json_get user_top_path, network_interface_accounting: { year: 2025, month: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)

      rows = accountings
      expect(rows.size).to be >= 2

      user_row = rows.detect { |row| resource_id(row['user']) == user.id }
      other_row = rows.detect { |row| resource_id(row['user']) == other_user.id }
      expected_keys = %w[user bytes bytes_in bytes_out packets packets_in packets_out year month]

      expect(user_row.keys).to include(*expected_keys)
      expect(user_row['bytes']).to eq(user_row['bytes_in'] + user_row['bytes_out'])
      expect(user_row['packets']).to eq(user_row['packets_in'] + user_row['packets_out'])
      expect(user_row['bytes']).to eq(560)

      expect(other_row['bytes']).to eq(50)

      expect(resource_id(rows.first['user'])).to eq(user.id)
      expect(rows.first['bytes']).to eq(560)
    end

    it 'supports limit pagination' do
      as(admin) { json_get user_top_path, network_interface_accounting: { year: 2025, month: 1, limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(accountings.size).to eq(1)
    end

    it 'supports from_bytes pagination' do
      boundary = 560
      as(admin) { json_get user_top_path, network_interface_accounting: { year: 2025, month: 1, from_bytes: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(accountings.size).to eq(1)
      expect(resource_id(accountings.first['user'])).to eq(other_user.id)
      expect(accountings.first['bytes']).to be < boundary
    end

    it 'filters by environment' do
      as(admin) do
        json_get user_top_path, network_interface_accounting: {
          year: 2025,
          month: 1,
          environment: SpecSeed.other_environment.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      expect(accountings.size).to eq(1)
      expect(resource_id(accountings.first['user'])).to eq(user.id)
      expect(accountings.first['bytes']).to eq(10)
    end
  end
end
