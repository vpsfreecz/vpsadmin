# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::ClusterResource' do
  before do
    header 'Accept', 'application/json'

    ClusterResource.create!(
      name: 'spec_res_a',
      label: 'Spec Res A',
      min: 1,
      max: 10,
      stepsize: 1,
      resource_type: :numeric
    )

    ClusterResource.create!(
      name: 'spec_res_b',
      label: 'Spec Res B',
      min: 5,
      max: 50,
      stepsize: 5,
      resource_type: :numeric
    )
  end

  def index_path
    vpath('/cluster_resources')
  end

  def show_path(id)
    vpath("/cluster_resources/#{id}")
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

  def cluster_resources
    json.dig('response', 'cluster_resources')
  end

  def cluster_resource
    json.dig('response', 'cluster_resource')
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

    it 'allows authenticated users to list resources' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      names = cluster_resources.map { |row| row['name'] }
      expect(names).to include('spec_res_a', 'spec_res_b')

      row = cluster_resources.find { |item| item['name'] == 'spec_res_a' }
      expect(row).to include('id', 'name', 'label', 'min', 'max', 'stepsize')
      expect(row).not_to include('resource_type', 'allocate_chain', 'free_chain')
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.user) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(ClusterResource.count)
    end

    it 'supports limit pagination' do
      as(SpecSeed.user) { json_get index_path, cluster_resource: { limit: 1 } }

      expect_status(200)
      expect(cluster_resources.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = ClusterResource.find_by!(name: 'spec_res_a').id
      as(SpecSeed.user) { json_get index_path, cluster_resource: { from_id: boundary } }

      expect_status(200)
      ids = cluster_resources.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      id = ClusterResource.find_by!(name: 'spec_res_a').id
      json_get show_path(id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows a resource for authenticated users' do
      id = ClusterResource.find_by!(name: 'spec_res_a').id
      as(SpecSeed.user) { json_get show_path(id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cluster_resource['id']).to eq(id)
      expect(cluster_resource['name']).to eq('spec_res_a')
      expect(cluster_resource['label']).to eq('Spec Res A')
      expect(cluster_resource['stepsize']).to eq(1)
      expect(cluster_resource['min']).not_to be_nil
      expect(cluster_resource['max']).not_to be_nil
      expect(cluster_resource).not_to include('resource_type', 'allocate_chain', 'free_chain')
    end

    it 'returns 404 for unknown resource' do
      missing = ClusterResource.maximum(:id).to_i + 100
      as(SpecSeed.user) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, cluster_resource: { name: 'x', label: 'X', min: 1, max: 2, stepsize: 1 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post index_path, cluster_resource: { name: 'x', label: 'X', min: 1, max: 2, stepsize: 1 }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a numeric resource with default resource_type' do
      as(SpecSeed.admin) do
        json_post index_path, cluster_resource: {
          name: 'spec_created',
          label: 'Spec Created',
          min: 1,
          max: 2,
          stepsize: 1
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      record = ClusterResource.find_by!(name: 'spec_created')
      expect(record.label).to eq('Spec Created')
      expect(record.resource_type).to eq('numeric')

      expect(cluster_resource['resource_type']).to eq('numeric') if cluster_resource
    end

    it 'returns validation errors for missing name' do
      as(SpecSeed.admin) do
        json_post index_path, cluster_resource: { label: 'X', min: 1, max: 2, stepsize: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('name')
    end

    it 'returns validation errors for duplicate name' do
      as(SpecSeed.admin) do
        json_post index_path, cluster_resource: { name: 'spec_res_a', label: 'Dup', min: 1, max: 2, stepsize: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('name')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      id = ClusterResource.find_by!(name: 'spec_res_a').id
      json_put show_path(id), cluster_resource: { label: 'Changed' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      id = ClusterResource.find_by!(name: 'spec_res_a').id
      as(SpecSeed.user) { json_put show_path(id), cluster_resource: { label: 'Changed' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update and returns the object' do
      id = ClusterResource.find_by!(name: 'spec_res_a').id
      as(SpecSeed.admin) { json_put show_path(id), cluster_resource: { label: 'Changed', stepsize: 2 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cluster_resource).to be_a(Hash)
      expect(cluster_resource['label']).to eq('Changed')
      expect(cluster_resource['stepsize']).to eq(2)

      record = ClusterResource.find(id)
      expect(record.label).to eq('Changed')
      expect(record.stepsize).to eq(2)
    end

    it 'returns validation errors for invalid label' do
      id = ClusterResource.find_by!(name: 'spec_res_a').id
      as(SpecSeed.admin) { json_put show_path(id), cluster_resource: { label: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('label')
    end
  end
end
