# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Cluster' do
  before do
    header 'Accept', 'application/json'
  end

  def show_path
    vpath('/cluster')
  end

  def public_stats_path
    vpath('/cluster/public_stats')
  end

  def full_stats_path
    vpath('/cluster/full_stats')
  end

  def search_path
    vpath('/cluster/search')
  end

  def generate_migration_keys_path
    vpath('/cluster/generate_migration_keys')
  end

  def set_maintenance_path
    vpath('/cluster/set_maintenance')
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

  def cluster_obj
    json.dig('response', 'cluster') || json['response'] || {}
  end

  def full_stats_obj
    json.dig('response', 'cluster') || json['response'] || {}
  end

  def search_results
    json.dig('response', 'clusters') || json['response'] || []
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def response_action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_environment!(label_prefix: 'Spec Env Cluster Lock')
    suffix = SecureRandom.hex(4)

    Environment.create!(
      label: "#{label_prefix} #{suffix}",
      domain: "spec-cluster-#{suffix}.test",
      user_ip_ownership: false
    )
  end

  def create_ip!(addr:, network:, user: nil, netif: nil)
    IpAddress.create!(
      ip_addr: addr,
      prefix: network.split_prefix,
      size: 1,
      network: network,
      user: user,
      network_interface: netif
    )
  end

  def create_node_status!(node:, created_at: nil, updated_at: nil)
    NodeCurrentStatus.where(node: node).delete_all

    attrs = {
      node: node,
      vpsadmin_version: 'spec',
      kernel: 'spec',
      update_count: 1
    }
    attrs[:created_at] = created_at if created_at
    attrs[:updated_at] = updated_at if updated_at

    NodeCurrentStatus.create!(attrs)
  end

  describe 'API description' do
    it 'includes cluster endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'cluster#show',
        'cluster#public_stats',
        'cluster#full_stats',
        'cluster#search',
        'cluster#generate_migration_keys',
        'cluster#set_maintenance'
      )
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal user' do
      as(SpecSeed.user) { json_get show_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cluster_obj.keys).to include('maintenance_lock', 'maintenance_lock_reason')
    end

    it 'reports no maintenance lock by default' do
      MaintenanceLock.where(class_name: 'Cluster', row_id: nil).delete_all

      as(SpecSeed.user) { json_get show_path }

      expect_status(200)
      expect(cluster_obj['maintenance_lock']).to be(false)
      expect(cluster_obj['maintenance_lock_reason']).to be_nil.or eq('')
    end

    it 'reports active lock' do
      MaintenanceLock.create!(
        class_name: 'Cluster',
        row_id: nil,
        active: true,
        reason: 'Spec reason',
        user: SpecSeed.admin
      )

      as(SpecSeed.user) { json_get show_path }

      expect_status(200)
      expect(cluster_obj['maintenance_lock']).to be(true)
      expect(cluster_obj['maintenance_lock_reason']).to eq('Spec reason')
    end
  end

  describe 'PublicStats' do
    let(:network_v4) { SpecSeed.network_v4 }

    it 'allows unauthenticated access' do
      json_get public_stats_path

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cluster_obj.keys).to include('user_count', 'vps_count', 'ipv4_left')
      expect(cluster_obj['user_count']).to be_a(Integer)
      expect(cluster_obj['vps_count']).to be_a(Integer)
      expect(cluster_obj['ipv4_left']).to be_a(Integer)
    end

    it 'returns correct ipv4_left' do
      create_ip!(addr: '192.0.2.200', network: network_v4)
      create_ip!(addr: '192.0.2.201', network: network_v4)
      create_ip!(addr: '192.0.2.202', network: network_v4, user: SpecSeed.user)

      json_get public_stats_path

      expect_status(200)

      expected = IpAddress.joins(:network).where(
        user: nil,
        network_interface: nil,
        networks: { ip_version: 4, role: Network.roles[:public_access] }
      ).count

      expect(cluster_obj['ipv4_left']).to eq(expected)
    end

    it 'works for authenticated users as well' do
      as(SpecSeed.user) { json_get public_stats_path }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'FullStats' do
    it 'rejects unauthenticated access' do
      json_get full_stats_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(SpecSeed.user) { json_get full_stats_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get full_stats_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin and returns the full stats hash' do
      create_node_status!(node: SpecSeed.node)
      create_node_status!(node: SpecSeed.other_node,
                          created_at: 10.minutes.ago,
                          updated_at: 10.minutes.ago)

      as(SpecSeed.admin) { json_get full_stats_path }

      expect_status(200)
      expect(json['status']).to be(true)

      expect(full_stats_obj.keys).to include(
        'nodes_online',
        'node_count',
        'vps_running',
        'vps_stopped',
        'vps_suspended',
        'vps_deleted',
        'vps_count',
        'user_active',
        'user_suspended',
        'user_deleted',
        'user_count',
        'ipv4_used',
        'ipv4_count'
      )

      t = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      expected = {
        'nodes_online' => Node.joins(:node_current_status).where(
          "TIMEDIFF(?, node_current_statuses.created_at) <= CAST('00:02:30' AS TIME) OR " \
          "TIMEDIFF(?, node_current_statuses.updated_at) <= CAST('00:02:30' AS TIME)",
          t, t
        ).count,
        'node_count' => Node.all.count,
        'vps_running' => Vps.joins(:vps_current_status).where(
          vps_current_statuses: { is_running: true }
        ).count,
        'vps_stopped' => Vps.joins(:vps_current_status).where(
          vps_current_statuses: { is_running: false }
        ).count,
        'vps_suspended' => Vps.joins(:user).where(
          'users.object_state = ? OR vpses.object_state = ?',
          User.object_states['suspended'], Vps.object_states['suspended']
        ).count,
        'vps_deleted' => Vps.unscoped.where(
          object_state: Vps.object_states['soft_delete']
        ).count,
        'vps_count' => Vps.unscoped.all.count,
        'user_active' => User.where(
          object_state: User.object_states['active']
        ).count,
        'user_suspended' => User.where(
          object_state: User.object_states['suspended']
        ).count,
        'user_deleted' => User.unscoped.where(
          object_state: User.object_states['soft_delete']
        ).count,
        'user_count' => User.unscoped.all.count,
        'ipv4_used' => IpAddress.joins(:network).where.not(network_interface: nil).where(
          networks: {
            ip_version: 4,
            role: Network.roles[:public_access]
          }
        ).count,
        'ipv4_count' => IpAddress.joins(:network).where(
          networks: {
            ip_version: 4,
            role: Network.roles[:public_access]
          }
        ).count
      }

      expected.each do |key, value|
        expect(full_stats_obj[key]).to eq(value)
        expect(full_stats_obj[key]).to be_a(Integer)
      end
    end
  end

  describe 'Search' do
    it 'rejects unauthenticated access' do
      json_post search_path, cluster: { value: 'user' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(SpecSeed.user) { json_post search_path, cluster: { value: 'user' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post search_path, cluster: { value: 'user' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'returns validation error for missing value' do
      as(SpecSeed.admin) { json_post search_path, cluster: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('value')
    end

    it 'returns user results for login search' do
      as(SpecSeed.admin) { json_post search_path, cluster: { value: 'user' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(search_results).to be_an(Array)

      result = search_results.find { |row| row['resource'] == 'User' }
      expect(result).not_to be_nil
    end

    it 'returns user results for numeric id search' do
      as(SpecSeed.admin) { json_post search_path, cluster: { value: SpecSeed.user.id.to_s } }

      expect_status(200)
      expect(json['status']).to be(true)

      result = search_results.find do |row|
        row['resource'] == 'User' && row['id'].to_i == SpecSeed.user.id
      end

      expect(result).not_to be_nil
      expect(result['attribute'].to_s).to eq('id')
      expect(result['value'].to_s).to eq(SpecSeed.user.id.to_s)
    end

    it 'trims whitespace' do
      as(SpecSeed.admin) { json_post search_path, cluster: { value: ' user ' } }

      expect_status(200)

      result = search_results.find { |row| row['resource'] == 'User' }
      expect(result).not_to be_nil
    end
  end

  describe 'GenerateMigrationKeys' do
    it 'rejects unauthenticated access' do
      json_post generate_migration_keys_path, {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(SpecSeed.user) { json_post generate_migration_keys_path, {} }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post generate_migration_keys_path, {} }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a transaction chain' do
      ensure_signer_unlocked!

      allow(TransactionChains::Cluster::GenerateMigrationKeys).to receive(:fire) do
        chain = TransactionChain.create!(
          name: TransactionChains::Cluster::GenerateMigrationKeys.chain_name,
          type: TransactionChains::Cluster::GenerateMigrationKeys.name,
          state: :queued,
          size: 1,
          user: User.current,
          user_session: UserSession.current
        )
        [chain, nil]
      end

      expect do
        as(SpecSeed.admin) { json_post generate_migration_keys_path, {} }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_action_state_id.to_i).to be > 0
      expect(response_action_state_id.to_i).to eq(TransactionChain.order(:id).last.id)
    end
  end

  describe 'SetMaintenance' do
    let!(:maintenance_environment) { create_environment!(label_prefix: 'Spec Env Cluster Lock') }

    it 'rejects unauthenticated access' do
      json_post set_maintenance_path, cluster: { lock: true, reason: 'Spec reason' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(SpecSeed.user) { json_post set_maintenance_path, cluster: { lock: true, reason: 'Spec reason' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post set_maintenance_path, cluster: { lock: true, reason: 'Spec reason' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'returns validation error when lock is missing' do
      as(SpecSeed.admin) { json_post set_maintenance_path, cluster: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('lock')
    end

    it 'allows admin to lock cluster maintenance' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path, cluster: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      lock = MaintenanceLock.find_by!(class_name: 'Cluster', row_id: nil, active: true)
      expect(lock.reason).to eq('Spec reason')

      maintenance_environment.reload
      expect(maintenance_environment.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:master_lock))
      expect(maintenance_environment.maintenance_lock_reason).to eq('Spec reason')

      as(SpecSeed.user) { json_get show_path }

      expect_status(200)
      expect(cluster_obj['maintenance_lock']).to be(true)
      expect(cluster_obj['maintenance_lock_reason']).to eq('Spec reason')
    end

    it 'rejects locking an already locked cluster' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path, cluster: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      as(SpecSeed.admin) do
        json_post set_maintenance_path, cluster: { lock: true, reason: 'Spec again' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('already locked')
    end

    it 'allows admin to unlock maintenance' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path, cluster: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)

      as(SpecSeed.admin) do
        json_post set_maintenance_path, cluster: { lock: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      lock = MaintenanceLock.find_by(class_name: 'Cluster', row_id: nil, active: true)
      expect(lock).to be_nil

      maintenance_environment.reload
      expect(maintenance_environment.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:no))
      expect(maintenance_environment.maintenance_lock_reason).to be_nil

      as(SpecSeed.user) { json_get show_path }

      expect_status(200)
      expect(cluster_obj['maintenance_lock']).to be(false)
    end
  end
end
