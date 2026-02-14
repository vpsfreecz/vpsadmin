# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Export' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.support
    SpecSeed.network_v4
  end

  def index_path
    vpath('/exports')
  end

  def show_path(id)
    vpath("/exports/#{id}")
  end

  def host_index_path(export_id)
    vpath("/exports/#{export_id}/hosts")
  end

  def host_show_path(export_id, host_id)
    vpath("/exports/#{export_id}/hosts/#{host_id}")
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
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def exports
    json.dig('response', 'exports') || []
  end

  def export_obj
    json.dig('response', 'export') || json['response']
  end

  def hosts
    json.dig('response', 'hosts') || json.dig('response', 'export_hosts') || []
  end

  def host_obj
    json.dig('response', 'host') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def create_primary_pool!(node: SpecSeed.node)
    pool = Pool.new(
      node: node,
      label: "Spec Primary Pool #{SecureRandom.hex(3)}",
      filesystem: "spec_primary_#{SecureRandom.hex(4)}",
      role: :primary,
      export_root: '/export',
      max_datasets: 100,
      is_open: true
    )
    pool.save!
    pool
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

  def create_ip!(addr:, network:, user: nil, netif: nil)
    ip = IpAddress.create!(
      ip_addr: addr,
      prefix: network.split_prefix,
      size: 1,
      network: network,
      user: user,
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

  def create_private_export_network_with_ips!(location:, count:, user: nil)
    network = Network.create!(
      label: "Spec Export Net #{SecureRandom.hex(3)}",
      ip_version: 4,
      address: '198.51.100.0',
      prefix: 24,
      role: :private_access,
      managed: true,
      split_access: :no_access,
      split_prefix: 32,
      purpose: :export,
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

    count.times do |i|
      create_ip!(
        addr: "198.51.100.#{10 + i}",
        network: network,
        user: user
      )
    end

    network
  end

  def create_export_record!(dip:, user: nil, with_ip: false, **attrs)
    export = nil
    user ||= dip.dataset.user

    Uuid.generate_for_new_record! do |uuid|
      export = Export.new(
        dataset_in_pool: dip,
        snapshot_in_pool_clone: nil,
        snapshot_in_pool_clone_n: 0,
        user: user,
        all_vps: attrs.fetch(:all_vps, false),
        path: attrs.fetch(:path, "/export/#{dip.dataset.full_name}"),
        rw: attrs.fetch(:rw, true),
        sync: attrs.fetch(:sync, true),
        subtree_check: attrs.fetch(:subtree_check, false),
        root_squash: attrs.fetch(:root_squash, false),
        threads: attrs.fetch(:threads, 8),
        enabled: attrs.fetch(:enabled, true),
        object_state: :active,
        confirmed: :confirmed
      )
      export.uuid = uuid
      export.save!
      export
    end

    return export unless with_ip

    netif = NetworkInterface.create!(export: export, kind: :veth_routed, name: 'eth0')
    create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4, netif: netif)
    export.reload
  end

  def next_ip_octet
    @ip_octet ||= 9
    @ip_octet += 1
  end

  def create_export_host_record!(export:, ip_address:, rw: nil, sync: nil, subtree_check: nil, root_squash: nil)
    ExportHost.create!(
      export: export,
      ip_address: ip_address,
      rw: rw.nil? ? export.rw : rw,
      sync: sync.nil? ? export.sync : sync,
      subtree_check: subtree_check.nil? ? export.subtree_check : subtree_check,
      root_squash: root_squash.nil? ? export.root_squash : root_squash
    )
  end

  describe 'API description' do
    it 'includes export endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'export#index', 'export#show', 'export#create', 'export#update', 'export#delete',
        'export.host#index', 'export.host#show', 'export.host#create', 'export.host#update', 'export.host#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows only user exports for normal users' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip_user)
      export_other = create_export_record!(dip: dip_other)

      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = exports.map { |row| row['id'] }
      expect(ids).to include(export_user.id)
      expect(ids).not_to include(export_other.id)

      row = exports.find { |item| item['id'] == export_user.id }
      expect(row).not_to have_key('user')
      expect(row).not_to have_key('threads')
    end

    it 'allows support to list only their exports' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_support = create_dataset_in_pool!(user: SpecSeed.support, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip_user)
      support_export = create_export_record!(dip: dip_support)

      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      ids = exports.map { |row| row['id'] }
      expect(ids).to include(support_export.id)
      expect(ids).not_to include(export_user.id)
    end

    it 'allows admins to list all exports' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip_user)
      export_other = create_export_record!(dip: dip_other)

      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = exports.map { |row| row['id'] }
      expect(ids).to include(export_user.id, export_other.id)

      row = exports.find { |item| item['id'] == export_other.id }
      expect(rid(row['user'])).to eq(SpecSeed.other_user.id)
      expect(row['threads']).to eq(export_other.threads)
    end

    it 'allows admins to filter by user' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip_user)
      export_other = create_export_record!(dip: dip_other)

      as(SpecSeed.admin) { json_get index_path, export: { user: SpecSeed.user.id } }

      expect_status(200)
      ids = exports.map { |row| row['id'] }
      expect(ids).to include(export_user.id)
      expect(ids).not_to include(export_other.id)
    end

    it 'ignores user filter for non-admins' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip_user)
      export_other = create_export_record!(dip: dip_other)

      as(SpecSeed.user) { json_get index_path, export: { user: SpecSeed.other_user.id } }

      expect_status(200)
      ids = exports.map { |row| row['id'] }
      expect(ids).to include(export_user.id)
      expect(ids).not_to include(export_other.id)
    end

    it 'supports limit pagination' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      create_export_record!(dip: dip_user)
      create_export_record!(dip: dip_other)

      as(SpecSeed.admin) { json_get index_path, export: { limit: 1 } }

      expect_status(200)
      expect(exports.length).to eq(1)
    end

    it 'supports from_id pagination' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      create_export_record!(dip: dip_user)
      create_export_record!(dip: dip_other)

      boundary = Export.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, export: { from_id: boundary } }

      expect_status(200)
      ids = exports.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      create_export_record!(dip: dip_user)
      create_export_record!(dip: dip_other)

      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Export.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip_user)

      json_get show_path(export_user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show their export' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip_user)

      as(SpecSeed.user) { json_get show_path(export_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(export_obj['id']).to eq(export_user.id)
      expect(export_obj).not_to have_key('user')
      expect(export_obj).not_to have_key('threads')
    end

    it 'prevents user from showing other user export' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)

      as(SpecSeed.user) { json_get show_path(export_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any export' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)

      as(SpecSeed.admin) { json_get show_path(export_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(export_obj['id']).to eq(export_other.id)
      expect(rid(export_obj['user'])).to eq(SpecSeed.other_user.id)
      expect(export_obj['threads']).to eq(export_other.threads)
    end

    it 'returns 404 for missing id' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      create_export_record!(dip: dip_user)
      missing = Export.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      pool = create_primary_pool!(node: SpecSeed.node)
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: pool)
      create_private_export_network_with_ips!(location: pool.node.location, count: 1)

      json_post index_path, export: { dataset: dip.dataset.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to create an export for their dataset' do
      pool = create_primary_pool!(node: SpecSeed.node)
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: pool)
      create_private_export_network_with_ips!(location: pool.node.location, count: 2)
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.user) { json_post index_path, export: { dataset: dip.dataset.id } }
      end.to change(Export, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      export = Export.order(:id).last
      expect(export.user_id).to eq(SpecSeed.user.id)
      expect(export.dataset_in_pool_id).to eq(dip.id)
      expect(export.path).to be_present
      expect(export.network_interface).not_to be_nil
      expect(export.ip_addresses.count).to be >= 1
      expect(export.host_ip_addresses.count).to be >= 1

      expect(export_obj).not_to have_key('user')
      expect(export_obj).not_to have_key('threads')
    end

    it 'ignores threads for non-admin users' do
      pool = create_primary_pool!(node: SpecSeed.node)
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: pool)
      create_private_export_network_with_ips!(location: pool.node.location, count: 1)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_post index_path, export: { dataset: dip.dataset.id, threads: 16 } }

      expect_status(200)
      expect(json['status']).to be(true)
      export = Export.order(:id).last
      expect(export.threads).to eq(8)
    end

    it 'allows admin to set threads' do
      pool = create_primary_pool!(node: SpecSeed.node)
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: pool)
      create_private_export_network_with_ips!(location: pool.node.location, count: 1)
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_post index_path, export: { dataset: dip.dataset.id, threads: 16 } }

      expect_status(200)
      expect(json['status']).to be(true)
      export = Export.order(:id).last
      expect(export.threads).to eq(16)
      expect(export_obj['threads']).to eq(16)
      expect(rid(export_obj['user'])).to eq(SpecSeed.user.id)
    end

    it 'requires either dataset or snapshot' do
      as(SpecSeed.admin) { json_post index_path, export: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to match(/provide either dataset or snapshot/i)
    end

    it 'rejects when both dataset and snapshot are provided' do
      pool = create_primary_pool!(node: SpecSeed.node)
      dip = create_dataset_in_pool!(user: SpecSeed.admin, pool: pool)
      snapshot = Snapshot.create!(
        dataset: dip.dataset,
        name: "spec-snap-#{SecureRandom.hex(3)}"
      )

      as(SpecSeed.admin) do
        json_post index_path, export: { dataset: dip.dataset.id, snapshot: snapshot.id }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to match(/provide either dataset or snapshot/i)
    end

    it 'rejects duplicate exports for the same dataset' do
      pool = create_primary_pool!(node: SpecSeed.node)
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: pool)
      create_private_export_network_with_ips!(location: pool.node.location, count: 2)
      ensure_signer_unlocked!

      create_export_record!(dip: dip)

      as(SpecSeed.user) { json_post index_path, export: { dataset: dip.dataset.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to match(/already exported/i)
    end

    it 'denies user export on other user dataset' do
      pool = create_primary_pool!(node: SpecSeed.node)
      dip = create_dataset_in_pool!(user: SpecSeed.other_user, pool: pool)
      create_private_export_network_with_ips!(location: pool.node.location, count: 1)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_post index_path, export: { dataset: dip.dataset.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to match(/access denied/i)
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)

      json_put show_path(export_user.id), export: { rw: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'prevents user from updating other user export' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)

      as(SpecSeed.user) { json_put show_path(export_other.id), export: { rw: false } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'ignores threads for non-admin users' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      threads_before = export_user.threads

      as(SpecSeed.user) { json_put show_path(export_user.id), export: { threads: 16 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id).to be_nil
      expect(export_user.reload.threads).to eq(threads_before)
    end

    it 'applies db-only changes immediately' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)

      as(SpecSeed.user) { json_put show_path(export_user.id), export: { rw: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id).to be_nil
      expect(export_user.reload.rw).to be(false)
      expect(export_obj['rw']).to be(false)
    end

    it 'creates a chain when admin changes threads' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_put show_path(export_user.id), export: { threads: 16 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      chain = TransactionChain.find(action_state_id)
      expect(chain.state).to eq('queued')
      expect(chain.user_id).to eq(SpecSeed.admin.id)
      expect(TransactionChainConcern.where(
        transaction_chain_id: chain.id,
        class_name: 'Export',
        row_id: export_user.id
      ).exists?).to be(true)
      expect(chain.transactions.pluck(:handle)).to include(5407)
    end

    it 'creates a chain when admin toggles enabled' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_put show_path(export_user.id), export: { enabled: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(TransactionChain.where(id: action_state_id).exists?).to be(true)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip, with_ip: true)

      json_delete show_path(export_user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'prevents user from deleting other user export' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other, with_ip: true)

      as(SpecSeed.user) { json_delete show_path(export_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'queues export deletion for the owner' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip, with_ip: true)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_delete show_path(export_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      chain = TransactionChain.find(action_state_id)
      expect(chain).not_to be_nil
      expect(export_user.reload.confirmed).to eq(:confirm_destroy)
      expect(Export.where(id: export_user.id).exists?).to be(true)
    end
  end

  describe 'Host Index' do
    it 'rejects unauthenticated access' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)

      json_get host_index_path(export_user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists hosts only for user exports' do
      dip_user = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip_user)
      export_other = create_export_record!(dip: dip_other)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      other_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_user, ip_address: host_ip)
      other_host = create_export_host_record!(export: export_other, ip_address: other_ip)

      as(SpecSeed.user) { json_get host_index_path(export_user.id) }

      expect_status(200)
      ids = hosts.map { |row| row['id'] }
      expect(ids).to include(host.id)
      expect(ids).not_to include(other_host.id)
    end

    it 'prevents user from listing hosts for other exports' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)

      as(SpecSeed.user) { json_get host_index_path(export_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(hosts).to be_empty
    end

    it 'allows admin to list hosts for any export' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_other, ip_address: host_ip)

      as(SpecSeed.admin) { json_get host_index_path(export_other.id) }

      expect_status(200)
      ids = hosts.map { |row| row['id'] }
      expect(ids).to include(host.id)
    end
  end

  describe 'Host Show' do
    it 'rejects unauthenticated access' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_user, ip_address: host_ip)

      json_get host_show_path(export_user.id, host.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows host for export owner' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_user, ip_address: host_ip)

      as(SpecSeed.user) { json_get host_show_path(export_user.id, host.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(host_obj['id']).to eq(host.id)
    end

    it 'prevents user from showing host for other exports' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_other, ip_address: host_ip)

      as(SpecSeed.user) { json_get host_show_path(export_other.id, host.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for missing host id' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      missing = ExportHost.maximum(:id).to_i + 100

      as(SpecSeed.user) { json_get host_show_path(export_user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Host Create' do
    it 'rejects unauthenticated access' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)

      json_post host_index_path(export_user.id), host: { ip_address: ip.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to add a host to their export' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(
        dip: dip,
        rw: false,
        sync: true,
        subtree_check: true,
        root_squash: false
      )
      ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.user) { json_post host_index_path(export_user.id), host: { ip_address: ip.id } }
      end.to change(ExportHost, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      host = ExportHost.order(:id).last
      expect(host.export_id).to eq(export_user.id)
      expect(host.ip_address_id).to eq(ip.id)
      expect(host.rw).to eq(export_user.rw)
      expect(host.sync).to eq(export_user.sync)
      expect(host.subtree_check).to eq(export_user.subtree_check)
      expect(host.root_squash).to eq(export_user.root_squash)
    end

    it 'prevents user from adding host to other exports' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)
      ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_post host_index_path(export_other.id), host: { ip_address: ip.id } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'requires ip_address' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_post host_index_path(export_user.id), host: {} }

      expect_status(200)
      expect(json['status']).to be(false)

      if errors.empty?
        expect(msg).to match(/ip_address/i)
      else
        expect(errors).to include('ip_address')
      end
    end
  end

  describe 'Host Update' do
    it 'rejects unauthenticated access' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_user, ip_address: host_ip)

      json_put host_show_path(export_user.id, host.id), host: { rw: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'prevents user from updating host on other exports' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_other, ip_address: host_ip)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_put host_show_path(export_other.id, host.id), host: { rw: false } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'creates a chain when user updates host options' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_user, ip_address: host_ip)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_put host_show_path(export_user.id, host.id), host: { rw: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      expect(TransactionChainConcern.where(
        transaction_chain_id: action_state_id,
        class_name: 'Export',
        row_id: export_user.id
      ).exists?).to be(true)
    end
  end

  describe 'Host Delete' do
    it 'rejects unauthenticated access' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_user, ip_address: host_ip)

      json_delete host_show_path(export_user.id, host.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'prevents user from deleting host on other exports' do
      dip_other = create_dataset_in_pool!(user: SpecSeed.other_user, pool: SpecSeed.pool)
      export_other = create_export_record!(dip: dip_other)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_other, ip_address: host_ip)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_delete host_show_path(export_other.id, host.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'queues host deletion for export owner' do
      dip = create_dataset_in_pool!(user: SpecSeed.user, pool: SpecSeed.pool)
      export_user = create_export_record!(dip: dip)
      host_ip = create_ip!(addr: "192.0.2.#{next_ip_octet}", network: SpecSeed.network_v4)
      host = create_export_host_record!(export: export_user, ip_address: host_ip)
      ensure_signer_unlocked!

      as(SpecSeed.user) { json_delete host_show_path(export_user.id, host.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end
  end
end
