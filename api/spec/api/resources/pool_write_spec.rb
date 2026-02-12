# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Pool write actions' do # rubocop:disable RSpec/DescribeClass
  let(:pool) { Pool.find(SpecSeed.pool.id) }
  let(:other_pool) { Pool.find(SpecSeed.other_pool.id) }

  before do
    header 'Accept', 'application/json'
    pool
    other_pool
  end

  def index_path
    vpath('/pools')
  end

  def show_path(id)
    vpath("/pools/#{id}")
  end

  def set_maintenance_path(id)
    vpath("/pools/#{id}/set_maintenance")
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def pool_obj
    json.dig('response', 'pool') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
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

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def minimal_pool_payload(node_id: pool.node_id, role: 'hypervisor', overrides: {})
    suffix = SecureRandom.hex(4)

    payload = {
      node: node_id,
      label: "Spec Pool #{suffix}",
      filesystem: "spec_pool_#{suffix}",
      role: role
    }

    payload.merge!(overrides)
    payload
  end

  def create_pool!(label: 'Spec Pool Maintenance', node: pool.node)
    suffix = SecureRandom.hex(3)

    record = Pool.new(
      node: node,
      label: "#{label} #{suffix}",
      filesystem: "spec_pool_maint_#{suffix}",
      role: :hypervisor
    )
    record.save!
    record
  end

  describe 'API description' do
    it 'includes pool write endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('pool#create', 'pool#set_maintenance')
    end

    it 'documents pool create and set_maintenance inputs' do
      create_params = action_input_params('pool', 'create')
      maintenance_params = action_input_params('pool', 'set_maintenance')

      expect(create_params.keys).to include('node', 'label', 'filesystem', 'role')
      expect(maintenance_params.keys).to include('lock', 'reason')
    end
  end

  describe 'Create' do
    let(:payload) { minimal_pool_payload }

    it 'rejects unauthenticated access' do
      json_post index_path, pool: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, pool: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, pool: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create with minimal payload' do
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.admin) { json_post index_path, pool: payload }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(pool_obj).to be_a(Hash)
      expect(pool_obj['label']).to eq(payload[:label])
      expect(pool_obj['filesystem']).to eq(payload[:filesystem])
      expect(pool_obj['name']).to eq(payload[:filesystem])
      expect(pool_obj['role']).to eq(payload[:role])
      expect(resource_id(pool_obj['node'])).to eq(payload[:node])

      record = Pool.find_by!(filesystem: payload[:filesystem])
      expect(record.label).to eq(payload[:label])
      expect(record.node_id).to eq(payload[:node])
      expect(record.role).to eq(payload[:role])
    end

    it 'returns validation errors for missing label' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_post index_path, pool: payload.except(:label) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for missing filesystem' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_post index_path, pool: payload.except(:filesystem) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('filesystem')
    end
  end

  describe 'SetMaintenance' do
    let!(:maintenance_pool) { create_pool!(label: 'Spec Pool Maintenance') }

    it 'rejects unauthenticated access' do
      json_post set_maintenance_path(maintenance_pool.id), pool: { lock: true, reason: 'Spec reason' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post set_maintenance_path(maintenance_pool.id), pool: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_post set_maintenance_path(maintenance_pool.id), pool: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to lock maintenance' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_pool.id), pool: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      maintenance_pool.reload
      expect(maintenance_pool.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:lock))
      expect(maintenance_pool.maintenance_lock_reason).to eq('Spec reason')
    end

    it 'allows admin to unlock maintenance' do
      MaintenanceLock.lock_for(maintenance_pool, user: SpecSeed.admin, reason: 'Spec lock')
                     .lock!(maintenance_pool)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_pool.id), pool: { lock: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      maintenance_pool.reload
      expect(maintenance_pool.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:no))
      expect(maintenance_pool.maintenance_lock_reason).to be_nil
    end

    it 'returns validation errors for missing lock' do
      as(SpecSeed.admin) { json_post set_maintenance_path(maintenance_pool.id), pool: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('lock')
    end

    it 'rejects locking an already locked pool' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_pool.id), pool: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_pool.id), pool: { lock: true, reason: 'Spec again' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
    end
  end
end
