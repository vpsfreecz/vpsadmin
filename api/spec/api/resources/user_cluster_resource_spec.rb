# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User::ClusterResource' do
  before do
    header 'Accept', 'application/json'
  end

  def admin
    SpecSeed.admin
  end

  def support
    SpecSeed.support
  end

  def user
    SpecSeed.user
  end

  def other_user
    SpecSeed.other_user
  end

  def env
    SpecSeed.environment
  end

  def other_env
    SpecSeed.other_environment
  end

  def ipv4
    ClusterResource.find_by!(name: 'ipv4')
  end

  def memory
    ClusterResource.find_by!(name: 'memory')
  end

  def ucr_user_env_ipv4
    UserClusterResource.find_by!(user: user, environment: env, cluster_resource: ipv4)
  end

  def ucr_other_user_env_ipv4
    UserClusterResource.find_by!(user: other_user, environment: env, cluster_resource: ipv4)
  end

  def index_path(user_id)
    vpath("/users/#{user_id}/cluster_resources")
  end

  def show_path(user_id, id)
    vpath("/users/#{user_id}/cluster_resources/#{id}")
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

  def cluster_resources
    json.dig('response', 'cluster_resources') ||
      json.dig('response', 'user_cluster_resources') ||
      json.dig('response', 'resources') ||
      []
  end

  def cluster_resource_obj
    json.dig('response', 'cluster_resource') ||
      json.dig('response', 'user_cluster_resource') ||
      json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def row_environment_id(row)
    resource_id(row['environment']).to_i
  end

  def row_cluster_resource_id(row)
    resource_id(row['cluster_resource']).to_i
  end

  def num(value)
    value.respond_to?(:to_i) ? value.to_i : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_resource_uses!(ucr)
    ClusterResourceUse.create!(
      user_cluster_resource: ucr,
      class_name: 'Spec',
      table_name: 'spec',
      row_id: 1,
      value: 3,
      confirmed: :confirmed,
      enabled: true
    )

    ClusterResourceUse.create!(
      user_cluster_resource: ucr,
      class_name: 'Spec',
      table_name: 'spec',
      row_id: 2,
      value: 5,
      confirmed: :confirm_create,
      enabled: true
    )

    ClusterResourceUse.create!(
      user_cluster_resource: ucr,
      class_name: 'Spec',
      table_name: 'spec',
      row_id: 3,
      value: 7,
      confirmed: :confirmed,
      enabled: false
    )
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to list their own cluster resources' do
      as(user) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cluster_resources).not_to be_empty

      expect(cluster_resources.any? do |row|
        row_environment_id(row) == env.id && row_cluster_resource_id(row) == ipv4.id
      end).to be(true)

      expect(cluster_resources.any? do |row|
        row_environment_id(row) == other_env.id && row_cluster_resource_id(row) == ipv4.id
      end).to be(true)

      expect(cluster_resources).to all(include('id', 'environment', 'cluster_resource', 'value', 'used', 'free'))
    end

    it 'uses confirmed enabled resource uses for used/free' do
      create_resource_uses!(ucr_user_env_ipv4)

      as(user) do
        json_get index_path(user.id), cluster_resource: { environment: env.id }
      end

      expect_status(200)
      target = cluster_resources.find do |row|
        row_environment_id(row) == env.id && row_cluster_resource_id(row) == ipv4.id
      end

      expect(target).not_to be_nil
      expect(num(target['used'])).to eq(3)
      expect(num(target['free'])).to eq(num(target['value']) - 3)
    end

    it 'filters by environment' do
      as(user) do
        json_get index_path(user.id), cluster_resource: { environment: env.id }
      end

      expect_status(200)
      expect(cluster_resources).not_to be_empty
      expect(cluster_resources.all? { |row| row_environment_id(row) == env.id }).to be(true)
    end

    it 'allows admin to list cluster resources for another user' do
      as(admin) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'prevents non-admin from listing cluster resources for another user' do
      as(user) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('smell')
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get index_path(user.id), _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to be_a(Integer)
      expect(json.dig('response', '_meta', 'total_count')).to be > 0
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path(user.id), cluster_resource: { limit: 1 } }

      expect_status(200)
      expect(cluster_resources.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = ucr_user_env_ipv4.id
      as(admin) { json_get index_path(user.id), cluster_resource: { from_id: boundary } }

      expect_status(200)
      ids = cluster_resources.map { |row| row['id'].to_i }
      expect(ids.all? { |id| id > boundary }).to be(true)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user.id, ucr_user_env_ipv4.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show their own record' do
      create_resource_uses!(ucr_user_env_ipv4)

      as(user) { json_get show_path(user.id, ucr_user_env_ipv4.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cluster_resource_obj['id']).to eq(ucr_user_env_ipv4.id)
      expect(row_environment_id(cluster_resource_obj)).to eq(env.id)
      expect(row_cluster_resource_id(cluster_resource_obj)).to eq(ipv4.id)
      expect(num(cluster_resource_obj['used'])).to eq(3)
    end

    it 'allows admin to show other user record' do
      as(admin) { json_get show_path(other_user.id, ucr_other_user_env_ipv4.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cluster_resource_obj['id']).to eq(ucr_other_user_env_ipv4.id)
    end

    it 'prevents non-admin from showing other user record' do
      as(user) { json_get show_path(other_user.id, ucr_other_user_env_ipv4.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('smell')
    end

    it 'returns 404 for unknown record' do
      missing = UserClusterResource.maximum(:id).to_i + 100

      as(admin) { json_get show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path(user.id), cluster_resource: {
        environment: env.id,
        cluster_resource: memory.id,
        value: 2048
      }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) do
        json_post index_path(user.id), cluster_resource: {
          environment: env.id,
          cluster_resource: memory.id,
          value: 2048
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(support) do
        json_post index_path(support.id), cluster_resource: {
          environment: env.id,
          cluster_resource: memory.id,
          value: 2048
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a new user cluster resource' do
      as(admin) do
        json_post index_path(other_user.id), cluster_resource: {
          environment: env.id,
          cluster_resource: memory.id,
          value: 2048
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(row_environment_id(cluster_resource_obj)).to eq(env.id)
      expect(row_cluster_resource_id(cluster_resource_obj)).to eq(memory.id)
      expect(num(cluster_resource_obj['value'])).to eq(2048)

      record = UserClusterResource.find_by(
        user: other_user,
        environment: env,
        cluster_resource: memory
      )
      expect(record).not_to be_nil
    end

    it 'returns validation errors for missing cluster_resource' do
      as(admin) do
        json_post index_path(user.id), cluster_resource: {
          environment: env.id,
          value: 2048
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('Server error occurred')
    end

    it 'returns validation errors for missing environment' do
      as(admin) do
        json_post index_path(user.id), cluster_resource: {
          cluster_resource: memory.id,
          value: 2048
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('Server error occurred')
    end

    it 'returns validation errors for invalid value type' do
      as(admin) do
        json_post index_path(user.id), cluster_resource: {
          environment: env.id,
          cluster_resource: memory.id,
          value: 'nope'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(row_environment_id(cluster_resource_obj)).to eq(env.id)
      expect(row_cluster_resource_id(cluster_resource_obj)).to eq(memory.id)
      expect(num(cluster_resource_obj['value'])).to eq(0)

      record = UserClusterResource.find_by(
        user: user,
        environment: env,
        cluster_resource: memory
      )
      expect(record).not_to be_nil
      expect(record.value).to eq(0)
    end
  end
end
