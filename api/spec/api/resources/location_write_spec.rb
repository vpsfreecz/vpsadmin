# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Location write actions' do # rubocop:disable RSpec/DescribeClass
  let(:location) { SpecSeed.location }
  let(:other_location) { SpecSeed.other_location }

  before do
    header 'Accept', 'application/json'
    location
    other_location
  end

  def index_path
    vpath('/locations')
  end

  def show_path(id)
    vpath("/locations/#{id}")
  end

  def set_maintenance_path(id)
    vpath("/locations/#{id}/set_maintenance")
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

  def loc_obj
    json.dig('response', 'location') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def minimal_location_payload(label: 'Spec Location', domain: nil, environment_id: nil, overrides: {})
    suffix = SecureRandom.hex(4)

    payload = {
      label: "#{label} #{suffix}",
      domain: domain || "spec-#{suffix}.test",
      has_ipv6: true,
      remote_console_server: '',
      environment: environment_id || location.environment_id
    }

    payload.merge!(overrides)
    payload
  end

  def create_location!(label: 'Spec Location', domain: nil, environment: nil)
    suffix = SecureRandom.hex(4)

    Location.create!(
      label: "#{label} #{suffix}",
      domain: domain || "spec-#{suffix}.test",
      has_ipv6: true,
      remote_console_server: '',
      environment: environment || location.environment,
      description: 'Spec Location'
    )
  end

  describe 'API description' do
    it 'includes location write endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('location#create', 'location#update', 'location#set_maintenance')
    end
  end

  describe 'Create' do
    let(:payload) { minimal_location_payload }

    it 'rejects unauthenticated access' do
      json_post index_path, location: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, location: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, location: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create with minimal payload' do
      as(SpecSeed.admin) { json_post index_path, location: payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(loc_obj).to be_a(Hash)
      expect(loc_obj['label']).to eq(payload[:label])
      expect(loc_obj['domain']).to eq(payload[:domain])
      expect(loc_obj['has_ipv6']).to be(true)

      record = Location.find_by!(label: payload[:label])
      expect(record.domain).to eq(payload[:domain])
      expect(record.has_ipv6).to be(true)
      expect(record.remote_console_server).to eq('')
      expect(record.environment_id).to eq(payload[:environment])
    end

    it 'returns validation errors for missing label' do
      as(SpecSeed.admin) { json_post index_path, location: payload.except(:label) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for missing domain' do
      as(SpecSeed.admin) { json_post index_path, location: payload.except(:domain) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('domain')
    end

    it 'returns validation errors for missing environment' do
      as(SpecSeed.admin) { json_post index_path, location: payload.except(:environment) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('environment')
    end

    it 'returns validation errors for missing has_ipv6' do
      as(SpecSeed.admin) { json_post index_path, location: payload.except(:has_ipv6) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('has_ipv6')
    end
  end

  describe 'Update' do
    let!(:update_location) { create_location!(label: 'Spec Location Update') }

    it 'rejects unauthenticated access' do
      json_put show_path(update_location.id), location: { label: 'Spec Location Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(update_location.id), location: { label: 'Spec Location Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put show_path(update_location.id), location: { label: 'Spec Location Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update and returns the object' do
      as(SpecSeed.admin) do
        json_put show_path(update_location.id), location: {
          label: 'Spec Location Updated',
          description: 'Spec Location Updated'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(loc_obj).to be_a(Hash)
      expect(loc_obj['label']).to eq('Spec Location Updated')
      expect(loc_obj['description']).to eq('Spec Location Updated')

      record = Location.find(update_location.id)
      expect(record.label).to eq('Spec Location Updated')
      expect(record.description).to eq('Spec Location Updated')
    end

    it 'returns validation errors for invalid domain' do
      as(SpecSeed.admin) { json_put show_path(update_location.id), location: { domain: '??' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('domain')
    end

    it 'returns validation errors for invalid has_ipv6' do
      as(SpecSeed.admin) { json_put show_path(update_location.id), location: { has_ipv6: nil } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('has_ipv6')
    end
  end

  describe 'SetMaintenance' do
    let!(:maintenance_location) { create_location!(label: 'Spec Location Maintenance') }

    it 'rejects unauthenticated access' do
      json_post set_maintenance_path(maintenance_location.id), location: { lock: true, reason: 'Spec reason' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post set_maintenance_path(maintenance_location.id), location: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_post set_maintenance_path(maintenance_location.id), location: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to lock maintenance' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_location.id), location: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      maintenance_location.reload
      expect(maintenance_location.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:lock))
      expect(maintenance_location.maintenance_lock_reason).to eq('Spec reason')
    end

    it 'allows admin to unlock maintenance' do
      MaintenanceLock.lock_for(maintenance_location, user: SpecSeed.admin, reason: 'Spec lock')
                     .lock!(maintenance_location)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_location.id), location: { lock: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      maintenance_location.reload
      expect(maintenance_location.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:no))
      expect(maintenance_location.maintenance_lock_reason).to be_nil
    end

    it 'returns validation errors for missing lock' do
      as(SpecSeed.admin) { json_post set_maintenance_path(maintenance_location.id), location: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('lock')
    end

    it 'rejects locking an already locked location' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_location.id), location: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(maintenance_location.id), location: { lock: true, reason: 'Spec again' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
    end
  end
end
