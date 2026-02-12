# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::HostIpAddress' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.location
    SpecSeed.node
    SpecSeed.pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path
    vpath('/host_ip_addresses')
  end

  def show_path(id)
    vpath("/host_ip_addresses/#{id}")
  end

  def assign_path(id)
    vpath("/host_ip_addresses/#{id}/assign")
  end

  def free_path(id)
    vpath("/host_ip_addresses/#{id}/free")
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

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def host_list
    list = json.dig('response', 'host_ip_addresses') || json['response'] || []
    return list if list.is_a?(Array)

    list['host_ip_addresses'] || []
  end

  def host_obj
    json.dig('response', 'host_ip_address') || json['response']
  end

  def host_addr(row)
    row['addr'] || row['ip_addr']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'includes host_ip_address endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'host_ip_address#index',
        'host_ip_address#show',
        'host_ip_address#create',
        'host_ip_address#update',
        'host_ip_address#delete',
        'host_ip_address#assign',
        'host_ip_address#free'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows accessible records for users' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      _other_vps, other_netif = create_vps_with_netif!(user: SpecSeed.other_user)
      user_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.0',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      other_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.8',
        prefix: network.split_prefix,
        size: 8,
        netif: other_netif
      )
      user_host = create_host_ip!(ip_address: user_ip, ip_addr: '198.51.100.1')
      other_host = create_host_ip!(ip_address: other_ip, ip_addr: '198.51.100.9')

      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = host_list.map { |row| row['id'] }
      expect(ids).to include(user_host.id)
      expect(ids).not_to include(other_host.id)
    end

    it 'shows all records for admins' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      _other_vps, other_netif = create_vps_with_netif!(user: SpecSeed.other_user)
      user_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.0',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      other_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.8',
        prefix: network.split_prefix,
        size: 8,
        netif: other_netif
      )
      user_host = create_host_ip!(ip_address: user_ip, ip_addr: '198.51.100.1')
      other_host = create_host_ip!(ip_address: other_ip, ip_addr: '198.51.100.9')

      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = host_list.map { |row| row['id'] }
      expect(ids).to include(user_host.id, other_host.id)
    end

    it 'filters by addr' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.0',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      create_host_ip!(ip_address: ip, ip_addr: '198.51.100.1')
      create_host_ip!(ip_address: ip, ip_addr: '198.51.100.2')

      as(SpecSeed.admin) { json_get index_path, host_ip_address: { addr: '198.51.100.2' } }

      expect_status(200)
      expect(json['status']).to be(true)
      addrs = host_list.map { |row| host_addr(row) }
      expect(addrs).to contain_exactly('198.51.100.2')
    end

    it 'filters by prefix' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.0',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.1')

      as(SpecSeed.admin) { json_get index_path, host_ip_address: { prefix: 29 } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = host_list.map { |row| row['id'] }
      expect(ids).to include(host.id)
    end

    it 'filters by size' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.0',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.1')

      as(SpecSeed.admin) { json_get index_path, host_ip_address: { size: 8 } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = host_list.map { |row| row['id'] }
      expect(ids).to include(host.id)
    end

    it 'filters by assigned' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.0',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      assigned = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.1', order: 0)
      unassigned = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.2', order: nil)

      as(SpecSeed.admin) { json_get index_path, host_ip_address: { assigned: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = host_list.map { |row| row['id'] }
      expect(ids).to include(assigned.id)
      expect(ids).not_to include(unassigned.id)

      as(SpecSeed.admin) { json_get index_path, host_ip_address: { assigned: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = host_list.map { |row| row['id'] }
      expect(ids).to include(unassigned.id)
      expect(ids).not_to include(assigned.id)
    end

    it 'filters by routed' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      routed_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.0',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      unrouted_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.8',
        prefix: network.split_prefix,
        size: 8,
        netif: nil
      )
      routed_host = create_host_ip!(ip_address: routed_ip, ip_addr: '198.51.100.1')
      unrouted_host = create_host_ip!(ip_address: unrouted_ip, ip_addr: '198.51.100.9')

      as(SpecSeed.admin) { json_get index_path, host_ip_address: { routed: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = host_list.map { |row| row['id'] }
      expect(ids).to include(routed_host.id)
      expect(ids).not_to include(unrouted_host.id)

      as(SpecSeed.admin) { json_get index_path, host_ip_address: { routed: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = host_list.map { |row| row['id'] }
      expect(ids).to include(unrouted_host.id)
      expect(ids).not_to include(routed_host.id)
    end
  end

  describe 'Show' do
    let(:show_data) do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      _other_vps, other_netif = create_vps_with_netif!(user: SpecSeed.other_user)
      user_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.16',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      other_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.24',
        prefix: network.split_prefix,
        size: 8,
        netif: other_netif
      )
      {
        user_host: create_host_ip!(ip_address: user_ip, ip_addr: '198.51.100.17'),
        other_host: create_host_ip!(ip_address: other_ip, ip_addr: '198.51.100.25')
      }
    end

    it 'rejects unauthenticated access' do
      host = show_data.fetch(:user_host)
      json_get show_path(host.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to view their host IP' do
      host = show_data.fetch(:user_host)
      as(SpecSeed.user) { json_get show_path(host.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(host_obj['id']).to eq(host.id)
    end

    it 'denies users access to other users host IPs' do
      host = show_data.fetch(:other_host)
      as(SpecSeed.user) { json_get show_path(host.id) }

      expect_status(404)
    end

    it 'allows admins to view other users host IPs' do
      host = show_data.fetch(:other_host)
      as(SpecSeed.admin) { json_get show_path(host.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(host_obj['id']).to eq(host.id)
    end
  end

  describe 'Create' do
    let(:create_data) do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      _other_vps, other_netif = create_vps_with_netif!(user: SpecSeed.other_user)
      {
        user_ip: create_ip_address!(
          network: network,
          ip_addr: '198.51.100.32',
          prefix: network.split_prefix,
          size: 8,
          netif: user_netif
        ),
        other_ip: create_ip_address!(
          network: network,
          ip_addr: '198.51.100.40',
          prefix: network.split_prefix,
          size: 8,
          netif: other_netif
        )
      }
    end

    it 'rejects unauthenticated access' do
      ip = create_data.fetch(:user_ip)
      json_post index_path, host_ip_address: { ip_address: ip.id, addr: '198.51.100.33' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'denies users creating host addresses under other users IPs' do
      ip = create_data.fetch(:other_ip)
      as(SpecSeed.user) do
        json_post index_path, host_ip_address: { ip_address: ip.id, addr: '198.51.100.41' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows users to create host addresses under their IPs' do
      ip = create_data.fetch(:user_ip)

      expect do
        as(SpecSeed.user) do
          json_post index_path, host_ip_address: { ip_address: ip.id, addr: '198.51.100.33' }
        end
      end.to change(HostIpAddress, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'rejects invalid host address format' do
      ip = create_data.fetch(:user_ip)
      as(SpecSeed.user) do
        json_post index_path, host_ip_address: { ip_address: ip.id, addr: 'not-an-ip' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('parse IP address')
    end

    it 'rejects host address outside of prefix' do
      ip = create_data.fetch(:user_ip)
      as(SpecSeed.user) do
        json_post index_path, host_ip_address: { ip_address: ip.id, addr: '198.51.100.250' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('does not belong')
    end

    it 'rejects duplicate host addresses' do
      ip = create_data.fetch(:user_ip)
      payload = { host_ip_address: { ip_address: ip.id, addr: '198.51.100.34' } }

      as(SpecSeed.user) { json_post index_path, payload }
      expect_status(200)
      expect(json['status']).to be(true)

      as(SpecSeed.user) { json_post index_path, payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('already exists')
    end
  end

  describe 'Update' do
    let(:update_data) do
      network = create_split_network!(location: SpecSeed.location)
      dns_zone = create_reverse_zone!(user: SpecSeed.admin)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      _other_vps, other_netif = create_vps_with_netif!(user: SpecSeed.other_user)
      user_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.48',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif,
        reverse_dns_zone: dns_zone
      )
      other_ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.56',
        prefix: network.split_prefix,
        size: 8,
        netif: other_netif,
        reverse_dns_zone: dns_zone
      )
      {
        user_host: create_host_ip!(ip_address: user_ip, ip_addr: '198.51.100.49'),
        other_host: create_host_ip!(ip_address: other_ip, ip_addr: '198.51.100.57')
      }
    end

    it 'rejects unauthenticated access' do
      host = update_data.fetch(:user_host)
      json_put show_path(host.id), host_ip_address: { reverse_record_value: 'ptr.example.test' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'denies access to other users host IPs' do
      host = update_data.fetch(:other_host)
      as(SpecSeed.user) do
        json_put show_path(host.id), host_ip_address: { reverse_record_value: 'ptr.example.test' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'rejects invalid reverse record values' do
      host = update_data.fetch(:user_host)
      as(SpecSeed.user) do
        json_put show_path(host.id), host_ip_address: { reverse_record_value: 'not a domain' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('reverse_record_value')
    end

    it 'sets and unsets PTR records' do
      host = update_data.fetch(:user_host)
      ensure_signer_unlocked!

      as(SpecSeed.user) do
        json_put show_path(host.id), host_ip_address: { reverse_record_value: 'ptr.example.test' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      host.reload
      record = host.reverse_dns_record
      expect(record).not_to be_nil
      expect(host.reverse_record_value).to end_with('.')
      expect(record.content).to eq('ptr.example.test.')

      as(SpecSeed.user) do
        json_put show_path(host.id), host_ip_address: { reverse_record_value: '' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      host.reload
      expect(host.reverse_dns_record_id).to be_nil
      expect(DnsRecord.where(id: record.id)).not_to exist
    end
  end

  describe 'Assign' do
    it 'rejects unauthenticated access' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.64',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.65')

      json_post assign_path(host.id), {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects assigning when the IP is not routed' do
      network = create_split_network!(location: SpecSeed.location)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.72',
        prefix: network.split_prefix,
        size: 8,
        netif: nil
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.73')

      as(SpecSeed.user) { json_post assign_path(host.id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('not assigned to any interface')
    end

    it 'denies assigning other users host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      _other_vps, other_netif = create_vps_with_netif!(user: SpecSeed.other_user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.80',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.81')

      as(SpecSeed.other_user) { json_post assign_path(host.id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'rejects assigning already assigned host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.88',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.89', order: 0)

      as(SpecSeed.user) { json_post assign_path(host.id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('already assigned')
    end

    it 'assigns host addresses to their interface' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.96',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.97', order: nil)

      ensure_signer_unlocked!

      expect do
        as(SpecSeed.user) { json_post assign_path(host.id), {} }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(host.reload.order).not_to be_nil
    end
  end

  describe 'Free' do
    it 'rejects unauthenticated access' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.104',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.105', order: 0)

      json_post free_path(host.id), {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects freeing when the IP is not routed' do
      network = create_split_network!(location: SpecSeed.location)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.112',
        prefix: network.split_prefix,
        size: 8,
        netif: nil
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.113', order: 0)

      as(SpecSeed.user) { json_post free_path(host.id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('not routed to any interface')
    end

    it 'denies freeing other users host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.120',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.121', order: 0)

      as(SpecSeed.other_user) { json_post free_path(host.id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'rejects freeing unassigned host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.128',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.129', order: nil)

      as(SpecSeed.user) { json_post free_path(host.id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('not assigned')
    end

    it 'rejects freeing addresses used for routing' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.136',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.137', order: 0)

      create_ip_address!(
        network: network,
        ip_addr: '198.51.100.144',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif,
        route_via: host
      )

      as(SpecSeed.user) { json_post free_path(host.id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('routed via this address')
    end

    it 'frees assigned host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.152',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.153', order: 0)

      ensure_signer_unlocked!

      expect do
        as(SpecSeed.user) { json_post free_path(host.id), {} }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.160',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.161', user_created: true)

      json_delete show_path(host.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'denies deleting other users host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.168',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.169', user_created: true)

      as(SpecSeed.other_user) { json_delete show_path(host.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'rejects deleting non-user-created host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.176',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.177', user_created: false)

      as(SpecSeed.user) { json_delete show_path(host.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('cannot be deleted')
    end

    it 'rejects deleting assigned host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.184',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.185', order: 0, user_created: true)

      as(SpecSeed.user) { json_delete show_path(host.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('in use')
    end

    it 'deletes user-created unassigned host addresses' do
      network = create_split_network!(location: SpecSeed.location)
      _user_vps, user_netif = create_vps_with_netif!(user: SpecSeed.user)
      ip = create_ip_address!(
        network: network,
        ip_addr: '198.51.100.192',
        prefix: network.split_prefix,
        size: 8,
        netif: user_netif
      )
      host = create_host_ip!(ip_address: ip, ip_addr: '198.51.100.193', order: nil, user_created: true)

      ensure_signer_unlocked!

      as(SpecSeed.user) { json_delete show_path(host.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(HostIpAddress.where(id: host.id)).not_to exist
    end
  end

  private

  def with_current_user(user)
    prev = ::User.current
    ::User.current = user
    yield
  ensure
    ::User.current = prev
  end

  def create_split_network!(location:, addr: '198.51.100.0', prefix: 24, split_prefix: 29)
    network = Network.create!(
      label: "Spec Net #{SecureRandom.hex(4)}",
      ip_version: 4,
      address: addr,
      prefix: prefix,
      role: :public_access,
      managed: true,
      split_access: :no_access,
      split_prefix: split_prefix,
      purpose: :any,
      primary_location: location
    )

    LocationNetwork.create!(
      location: location,
      network: network,
      primary: true,
      priority: 10,
      autopick: true,
      userpick: true
    )

    network
  end

  def create_reverse_zone!(user:, name: '100.51.198.in-addr.arpa.')
    with_current_user(user) do
      DnsZone.create!(
        user: user,
        name: name,
        label: "spec-reverse-#{SecureRandom.hex(4)}",
        zone_role: :reverse_role,
        zone_source: :internal_source,
        reverse_network_address: '198.51.100.0',
        reverse_network_prefix: 24,
        default_ttl: 3600,
        email: 'admin@example.test',
        confirmed: :confirmed
      )
    end
  end

  def create_dataset_in_pool!(pool:, user: SpecSeed.user)
    dataset = nil

    with_current_user(SpecSeed.admin) do
      dataset = Dataset.create!(
        name: "spec-#{SecureRandom.hex(4)}",
        user: user,
        user_editable: true,
        user_create: true,
        user_destroy: true,
        object_state: :active
      )
    end

    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, dataset_in_pool:)
    vps = Vps.new(
      user: user,
      node: node,
      hostname: "spec-vps-#{SecureRandom.hex(4)}",
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active
    )

    with_current_user(SpecSeed.admin) do
      vps.save!
    end

    vps
  rescue ActiveRecord::RecordInvalid
    vps.save!(validate: false)
    vps
  end

  def create_netif!(vps:, name: 'eth0', kind: :venet)
    NetworkInterface.create!(vps: vps, name: name, kind: kind)
  end

  def create_vps_with_netif!(user:)
    dataset_in_pool = create_dataset_in_pool!(pool: SpecSeed.pool, user: user)
    vps = create_vps!(user: user, node: SpecSeed.node, dataset_in_pool: dataset_in_pool)
    netif = create_netif!(vps: vps)
    [vps, netif]
  end

  def create_ip_address!(network:, ip_addr:, prefix:, size:, netif:, user: nil, reverse_dns_zone: nil, route_via: nil)
    IpAddress.create!(
      network: network,
      ip_addr: ip_addr,
      prefix: prefix,
      size: size,
      network_interface: netif,
      user: user,
      reverse_dns_zone: reverse_dns_zone,
      route_via: route_via
    )
  end

  def create_host_ip!(ip_address:, ip_addr:, order: nil, user_created: true)
    HostIpAddress.create!(
      ip_address: ip_address,
      ip_addr: ip_addr,
      order: order,
      user_created: user_created
    )
  end
end
