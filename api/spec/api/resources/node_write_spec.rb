# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Node write actions' do # rubocop:disable RSpec/DescribeClass
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

  def set_maintenance_path(id)
    vpath("/nodes/#{id}/set_maintenance")
  end

  def evacuate_path(id)
    vpath("/nodes/#{id}/evacuate")
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

  def node_obj
    json.dig('response', 'node') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def random_ipv4
    "192.0.2.#{200 + SecureRandom.random_number(40)}"
  end

  def minimal_node_payload(role: 'mailer', location_id: node.location_id, overrides: {})
    suffix = SecureRandom.hex(4)

    payload = {
      name: "spec-node-#{suffix}",
      type: role,
      location: location_id,
      ip_addr: random_ipv4,
      cpus: 2,
      total_memory: 2048,
      total_swap: 512
    }

    payload[:max_vps] = 5 if role == 'node'
    payload.merge!(overrides)
    payload
  end

  def create_node!(name_prefix: 'spec-node', location: node.location, role: :node)
    suffix = SecureRandom.hex(3)

    Node.create!(
      name: "#{name_prefix}-#{suffix}",
      location: location,
      role: role,
      hypervisor_type: :vpsadminos,
      ip_addr: random_ipv4,
      max_vps: 10,
      cpus: 2,
      total_memory: 2048,
      total_swap: 512,
      active: true
    )
  end

  describe 'API description' do
    it 'includes node write endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('node#create', 'node#update', 'node#set_maintenance', 'node#evacuate')
    end
  end

  describe 'Create' do
    let(:payload) { minimal_node_payload }

    it 'rejects unauthenticated access' do
      json_post index_path, node: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, node: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, node: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create with minimal payload' do
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.admin) { json_post index_path, node: payload }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = Node.find_by!(name: payload[:name])
      expect(record.location_id).to eq(payload[:location])
      expect(record.ip_addr).to eq(payload[:ip_addr])
      expect(record.role).to eq(payload[:type])
    end

    it 'returns validation errors for missing name' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_post index_path, node: payload.except(:name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('name')
    end

    it 'returns validation errors for invalid ip_addr' do
      ensure_signer_unlocked!

      invalid_payload = payload.merge(ip_addr: 'not-an-ip')
      as(SpecSeed.admin) { json_post index_path, node: invalid_payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('ip_addr')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(node.id), node: { name: 'spec-node-updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(node.id), node: { name: 'spec-node-updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put show_path(node.id), node: { name: 'spec-node-updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update node' do
      new_name = "spec-node-updated-#{SecureRandom.hex(3)}"
      new_ip = random_ipv4

      as(SpecSeed.admin) do
        json_put show_path(node.id), node: {
          name: new_name,
          ip_addr: new_ip
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      node.reload
      expect(node.name).to eq(new_name)
      expect(node.ip_addr).to eq(new_ip)
    end

    it 'returns validation errors for invalid ip_addr' do
      as(SpecSeed.admin) { json_put show_path(node.id), node: { ip_addr: '??' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('ip_addr')
    end
  end

  describe 'SetMaintenance' do
    let!(:maintenance_node) { create_node!(name_prefix: 'spec-node-maint') }

    it 'rejects unauthenticated access' do
      json_post set_maintenance_path(maintenance_node.id), node: { lock: true, reason: 'Spec reason' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post set_maintenance_path(maintenance_node.id), node: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_post set_maintenance_path(maintenance_node.id), node: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to lock maintenance' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_node.id), node: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      maintenance_node.reload
      expect(maintenance_node.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:lock))
      expect(maintenance_node.maintenance_lock_reason).to eq('Spec reason')
    end

    it 'allows admin to unlock maintenance' do
      MaintenanceLock.lock_for(maintenance_node, user: SpecSeed.admin, reason: 'Spec lock')
                     .lock!(maintenance_node)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_node.id), node: { lock: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      maintenance_node.reload
      expect(maintenance_node.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:no))
      expect(maintenance_node.maintenance_lock_reason).to be_nil
    end

    it 'returns validation errors for missing lock' do
      as(SpecSeed.admin) { json_post set_maintenance_path(maintenance_node.id), node: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('lock')
    end

    it 'rejects locking an already locked node' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_node.id), node: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_node.id), node: { lock: true, reason: 'Spec again' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
    end
  end

  describe 'Evacuate' do
    let!(:destination_node) { create_node!(name_prefix: 'spec-node-dst', location: node.location) }

    it 'rejects unauthenticated access' do
      json_post evacuate_path(node.id), node: { dst_node: destination_node.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post evacuate_path(node.id), node: { dst_node: destination_node.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post evacuate_path(node.id), node: { dst_node: destination_node.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to evacuate node and creates a transaction chain' do
      ensure_signer_unlocked!

      allow(TransactionChains::MigrationPlan::Mail).to receive(:fire) do |_plan|
        chain = TransactionChain.create!(
          name: TransactionChains::MigrationPlan::Mail.chain_name,
          type: TransactionChains::MigrationPlan::Mail.name,
          state: :queued,
          size: 1,
          user: User.current,
          user_session: UserSession.current
        )
        [chain, nil]
      end

      expect do
        as(SpecSeed.admin) { json_post evacuate_path(node.id), node: { dst_node: destination_node.id } }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      plan_id = json.dig('response', 'migration_plan_id') || json.dig('response', 'id')
      plan = plan_id ? MigrationPlan.find(plan_id) : MigrationPlan.order(:id).last
      expect(plan).not_to be_nil
      expect(plan.node_id).to eq(destination_node.id)
      expect(plan.user_id).to eq(SpecSeed.admin.id)
    end

    it 'returns validation errors for missing destination node' do
      as(SpecSeed.admin) { json_post evacuate_path(node.id), node: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('dst_node')
    end
  end
end
