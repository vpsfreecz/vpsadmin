# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Environment write actions' do # rubocop:disable RSpec/DescribeClass
  let(:environment) { SpecSeed.environment }
  let(:other_environment) { SpecSeed.other_environment }

  before do
    header 'Accept', 'application/json'
  end

  def index_path
    vpath('/environments')
  end

  def show_path(id)
    vpath("/environments/#{id}")
  end

  def set_maintenance_path(id)
    vpath("/environments/#{id}/set_maintenance")
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

  def env_obj
    json.dig('response', 'environment') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def minimal_env_payload(label_suffix: 'Created', domain: nil)
    suffix = SecureRandom.hex(4)

    {
      label: "Spec Env #{label_suffix} #{suffix}",
      domain: domain || "spec-#{suffix}.test",
      user_ip_ownership: true
    }
  end

  def create_environment!(label: 'Spec Env Local', domain: nil)
    suffix = SecureRandom.hex(3)

    Environment.create!(
      label: "#{label} #{suffix}",
      domain: domain || "spec-local-#{suffix}.test",
      user_ip_ownership: false
    )
  end

  describe 'API description' do
    it 'includes environment write endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('environment#create', 'environment#update', 'environment#set_maintenance')
    end
  end

  describe 'Create' do
    let(:payload) { minimal_env_payload }

    it 'rejects unauthenticated access' do
      json_post index_path, environment: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, environment: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, environment: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create with minimal payload' do
      as(SpecSeed.admin) { json_post index_path, environment: payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(env_obj).to be_a(Hash)
      expect(env_obj['label']).to eq(payload[:label])
      expect(env_obj['domain']).to eq(payload[:domain])

      record = Environment.find_by!(domain: payload[:domain])
      expect(record.label).to eq(payload[:label])
      expect(record.user_ip_ownership).to be(true)
    end

    it 'returns validation errors for missing label' do
      as(SpecSeed.admin) { json_post index_path, environment: payload.except(:label) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for missing domain' do
      as(SpecSeed.admin) { json_post index_path, environment: payload.except(:domain) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('domain')
    end

    it 'returns validation errors for invalid domain' do
      invalid_payload = payload.merge(domain: '??')
      as(SpecSeed.admin) { json_post index_path, environment: invalid_payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('domain')
    end
  end

  describe 'Update' do
    let!(:update_environment) { create_environment!(label: 'Spec Env Update') }

    it 'rejects unauthenticated access' do
      json_put show_path(update_environment.id), environment: { label: 'Spec Env Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_put show_path(update_environment.id), environment: { label: 'Spec Env Updated' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_put show_path(update_environment.id), environment: { label: 'Spec Env Updated' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update and returns the object' do
      as(SpecSeed.admin) do
        json_put show_path(update_environment.id), environment: {
          label: 'Spec Env Updated',
          can_create_vps: true
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(env_obj).to be_a(Hash)
      expect(env_obj['label']).to eq('Spec Env Updated')
      expect(env_obj['can_create_vps']).to be(true)

      record = Environment.find(update_environment.id)
      expect(record.label).to eq('Spec Env Updated')
      expect(record.can_create_vps).to be(true)
    end

    it 'returns validation errors for invalid label' do
      as(SpecSeed.admin) { json_put show_path(update_environment.id), environment: { label: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for invalid domain' do
      as(SpecSeed.admin) { json_put show_path(update_environment.id), environment: { domain: '??' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('domain')
    end
  end

  describe 'SetMaintenance' do
    let!(:maintenance_environment) { create_environment!(label: 'Spec Env Maintenance') }

    it 'rejects unauthenticated access' do
      json_post set_maintenance_path(maintenance_environment.id), environment: { lock: true, reason: 'Spec reason' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post set_maintenance_path(maintenance_environment.id), environment: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_post set_maintenance_path(maintenance_environment.id), environment: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to lock maintenance' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_environment.id), environment: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      maintenance_environment.reload
      expect(maintenance_environment.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:lock))
      expect(maintenance_environment.maintenance_lock_reason).to eq('Spec reason')
    end

    it 'allows admin to unlock maintenance' do
      MaintenanceLock.lock_for(maintenance_environment, user: SpecSeed.admin, reason: 'Spec lock')
                     .lock!(maintenance_environment)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_environment.id), environment: { lock: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      maintenance_environment.reload
      expect(maintenance_environment.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:no))
      expect(maintenance_environment.maintenance_lock_reason).to be_nil
    end

    it 'returns validation errors for missing lock' do
      as(SpecSeed.admin) { json_post set_maintenance_path(maintenance_environment.id), environment: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('lock')
    end

    it 'rejects locking an already locked environment' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_environment.id), environment: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_environment.id), environment: { lock: true, reason: 'Spec again' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
    end
  end
end
