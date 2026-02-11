# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Environment' do
  let(:environment) { SpecSeed.environment }
  let(:other_environment) { SpecSeed.other_environment }
  let(:extra_environment) { Environment.find_by!(label: 'Spec Env 3') }

  before do
    header 'Accept', 'application/json'

    Environment.find_or_create_by!(label: 'Spec Env 3') do |env|
      env.domain = 'spec3.test'
      env.user_ip_ownership = false
      env.description = 'Spec Env 3'
    end

    hypervisor_location = Location.create!(
      environment: environment,
      label: 'Spec Env Hypervisors',
      domain: 'spec-hv.test',
      has_ipv6: true,
      remote_console_server: ''
    )

    Node.create!(
      location: hypervisor_location,
      name: 'spec-hv-node',
      role: :node,
      ip_addr: '10.0.0.1',
      max_vps: 10,
      cpus: 4,
      total_memory: 1024,
      total_swap: 512,
      hypervisor_type: :vpsadminos
    )

    storage_location = Location.create!(
      environment: other_environment,
      label: 'Spec Env Storage',
      domain: 'spec-storage.test',
      has_ipv6: true,
      remote_console_server: ''
    )

    Node.create!(
      location: storage_location,
      name: 'spec-storage-node',
      role: :storage,
      ip_addr: '10.0.0.2',
      cpus: 4,
      total_memory: 1024,
      total_swap: 512
    )
  end

  def index_path
    vpath('/environments')
  end

  def show_path(id)
    vpath("/environments/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def envs
    json.dig('response', 'environments')
  end

  def env_obj
    json.dig('response', 'environment')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to list environments with limited output' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(envs).to be_an(Array)

      ids = envs.map { |row| row['id'] }
      expect(ids).to include(environment.id, other_environment.id)

      row = envs.find { |item| item['id'] == environment.id }
      expect(row).to include('id', 'label', 'description')
      expect(row['label']).to eq(environment.label)
      expect(row).not_to have_key('domain')
    end

    it 'allows support to list environments with limited output' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      row = envs.find { |item| item['id'] == environment.id }
      expect(row).not_to have_key('domain')
    end

    it 'allows admins to list environments with full output' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      row = envs.find { |item| item['id'] == environment.id }
      expect(row).to include('domain' => environment.domain)
      expect(row).to have_key('user_ip_ownership')
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, environment: { limit: 1 } }

      expect_status(200)
      expect(envs.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = other_environment.id
      as(SpecSeed.admin) { json_get index_path, environment: { from_id: boundary } }

      expect_status(200)
      ids = envs.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
      expect(ids).to include(extra_environment.id)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Environment.count)
    end

    it 'filters by has_hypervisor' do
      as(SpecSeed.admin) { json_get index_path, environment: { has_hypervisor: true } }

      expect_status(200)
      ids = envs.map { |row| row['id'] }
      expect(ids).to contain_exactly(environment.id)
    end

    it 'filters by has_storage' do
      as(SpecSeed.admin) { json_get index_path, environment: { has_storage: true } }

      expect_status(200)
      ids = envs.map { |row| row['id'] }
      expect(ids).to contain_exactly(other_environment.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(environment.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show environments with limited output' do
      as(SpecSeed.user) { json_get show_path(environment.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(env_obj['id']).to eq(environment.id)
      expect(env_obj['label']).to eq(environment.label)
      expect(env_obj).to have_key('description')
      expect(env_obj).not_to have_key('domain')
    end

    it 'allows support to show environments with limited output' do
      as(SpecSeed.support) { json_get show_path(other_environment.id) }

      expect_status(200)
      expect(env_obj['id']).to eq(other_environment.id)
      expect(env_obj).not_to have_key('domain')
    end

    it 'allows admins to show environments with full output' do
      as(SpecSeed.admin) { json_get show_path(environment.id) }

      expect_status(200)
      expect(env_obj['id']).to eq(environment.id)
      expect(env_obj['label']).to eq(environment.label)
      expect(env_obj['domain']).to eq(environment.domain)
      expect(env_obj).to have_key('user_ip_ownership')
    end

    it 'returns 404 for unknown environment' do
      missing = Environment.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
