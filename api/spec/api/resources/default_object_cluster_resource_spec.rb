# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::DefaultObjectClusterResource' do
  let!(:cpu_resource) do
    ClusterResource.create!(
      name: 'spec_do_cr_cpu',
      label: 'Spec DO CR CPU',
      min: 1,
      max: 10,
      stepsize: 1,
      resource_type: :numeric
    )
  end

  let!(:mem_resource) do
    ClusterResource.create!(
      name: 'spec_do_cr_mem',
      label: 'Spec DO CR MEM',
      min: 1,
      max: 10,
      stepsize: 1,
      resource_type: :numeric
    )
  end

  let!(:cpu_default) do
    DefaultObjectClusterResource.create!(
      environment: environment,
      cluster_resource: cpu_resource,
      class_name: 'Vps',
      value: 100
    )
  end

  let!(:mem_default) do
    DefaultObjectClusterResource.create!(
      environment: environment,
      cluster_resource: mem_resource,
      class_name: 'Vps',
      value: 200
    )
  end

  let!(:other_env_default) do
    DefaultObjectClusterResource.create!(
      environment: other_environment,
      cluster_resource: cpu_resource,
      class_name: 'Vps',
      value: 300
    )
  end

  before do
    header 'Accept', 'application/json'
  end

  def environment
    SpecSeed.environment
  end

  def other_environment
    SpecSeed.other_environment
  end

  def index_path
    vpath('/default_object_cluster_resources')
  end

  def show_path(id)
    vpath("/default_object_cluster_resources/#{id}")
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

  def default_object_cluster_resources
    json.dig('response', 'default_object_cluster_resources')
  end

  def default_object_cluster_resource
    json.dig('response', 'default_object_cluster_resource')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path, default_object_cluster_resource: {
        environment: environment.id,
        class_name: 'Vps'
      }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists default object cluster resources for an environment and class name' do
      as(SpecSeed.user) do
        json_get index_path, default_object_cluster_resource: {
          environment: environment.id,
          class_name: 'Vps'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      ids = default_object_cluster_resources.map { |row| row['id'] }
      expect(ids).to include(cpu_default.id, mem_default.id)
      expect(ids).not_to include(other_env_default.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(cpu_default.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows a default object cluster resource for authenticated users' do
      as(SpecSeed.user) { json_get show_path(cpu_default.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(default_object_cluster_resource['id']).to eq(cpu_default.id)
      expect(default_object_cluster_resource['class_name']).to eq('Vps')
    end

    it 'returns 404 for unknown resource' do
      missing = DefaultObjectClusterResource.maximum(:id).to_i + 100
      as(SpecSeed.user) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, default_object_cluster_resource: {
        environment: environment.id,
        cluster_resource: cpu_resource.id,
        class_name: 'Dataset',
        value: 123
      }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post index_path, default_object_cluster_resource: {
          environment: environment.id,
          cluster_resource: cpu_resource.id,
          class_name: 'Dataset',
          value: 123
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a default object cluster resource' do
      as(SpecSeed.admin) do
        json_post index_path, default_object_cluster_resource: {
          environment: environment.id,
          cluster_resource: cpu_resource.id,
          class_name: 'Dataset',
          value: 123
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      created = DefaultObjectClusterResource.find_by!(
        environment: environment,
        cluster_resource: cpu_resource,
        class_name: 'Dataset'
      )
      expect(created.value.to_s).to eq('123')
      expect(default_object_cluster_resource['class_name']).to eq('Dataset') if default_object_cluster_resource
    end

    it 'returns validation errors for missing value' do
      as(SpecSeed.admin) do
        json_post index_path, default_object_cluster_resource: {
          environment: environment.id,
          cluster_resource: cpu_resource.id,
          class_name: 'Dataset'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('value')
    end
  end

  describe 'Update' do
    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(cpu_default.id), default_object_cluster_resource: { value: 150 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update the value' do
      as(SpecSeed.admin) { json_put show_path(cpu_default.id), default_object_cluster_resource: { value: 150 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(default_object_cluster_resource).to be_a(Hash)
      expect(default_object_cluster_resource['value'].to_s).to eq('150')

      record = DefaultObjectClusterResource.find(cpu_default.id)
      expect(record.value.to_s).to eq('150')
    end
  end

  describe 'Delete' do
    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(cpu_default.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete' do
      as(SpecSeed.admin) { json_delete show_path(cpu_default.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(DefaultObjectClusterResource.where(id: cpu_default.id)).to be_empty
    end
  end
end
