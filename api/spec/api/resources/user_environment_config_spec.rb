# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User::EnvironmentConfig' do
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

  def user_cfg_env
    EnvironmentUserConfig.find_by!(user: user, environment: env)
  end

  def user_cfg_other_env
    EnvironmentUserConfig.find_by!(user: user, environment: other_env)
  end

  def other_user_cfg_env
    EnvironmentUserConfig.find_by!(user: other_user, environment: env)
  end

  def index_path(user_id)
    vpath("/users/#{user_id}/environment_configs")
  end

  def show_path(user_id, cfg_id)
    vpath("/users/#{user_id}/environment_configs/#{cfg_id}")
  end

  def update_path(user_id, cfg_id)
    show_path(user_id, cfg_id)
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def environment_configs
    json.dig('response', 'environment_configs') ||
      json.dig('response', 'user_environment_configs') ||
      json.dig('response', 'configs') ||
      []
  end

  def environment_config
    json.dig('response', 'environment_config') ||
      json.dig('response', 'user_environment_config') ||
      json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def resource_id(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'includes user environment config endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'user.environment_config#index',
        'user.environment_config#show',
        'user.environment_config#update'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal user to list their own configs' do
      as(user) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(environment_configs).to be_a(Array)
      expect(environment_configs.length).to be >= 2

      ids = environment_configs.map { |row| row['id'] }
      expect(ids).to include(user_cfg_env.id, user_cfg_other_env.id)

      expect(environment_configs).to all(
        include(
          'id',
          'environment',
          'can_create_vps',
          'can_destroy_vps',
          'vps_lifetime',
          'max_vps_count'
        )
      )
      expect(environment_configs).to all(satisfy { |row| !row.has_key?('default') })
    end

    it 'denies normal user listing another user configs' do
      as(user) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows admin to list any user configs and includes default' do
      as(admin) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(environment_configs).not_to be_empty

      expect(environment_configs).to all(include('default'))
    end

    it 'filters by environment' do
      as(admin) { json_get index_path(user.id), environment_config: { environment: env.id } }

      expect_status(200)
      expect(environment_configs.length).to eq(1)
      expect(resource_id(environment_configs.first['environment']).to_i).to eq(env.id)
    end

    it 'supports meta count' do
      as(admin) { json_get index_path(user.id), _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(
        EnvironmentUserConfig.where(user: user).count
      )
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path(user.id), environment_config: { limit: 1 } }

      expect_status(200)
      expect(environment_configs.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = EnvironmentUserConfig.where(user: user).order(:id).first.id

      as(admin) { json_get index_path(user.id), environment_config: { from_id: boundary } }

      expect_status(200)
      ids = environment_configs.map { |row| row['id'].to_i }
      expect(ids).not_to be_empty
      expect(ids.all? { |id| id > boundary }).to be(true)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user.id, user_cfg_env.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal user to show their own config' do
      as(user) { json_get show_path(user.id, user_cfg_env.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(environment_config['id']).to eq(user_cfg_env.id)
      expect(resource_id(environment_config['environment']).to_i).to eq(env.id)
      expect(environment_config).to include(
        'can_create_vps', 'can_destroy_vps', 'vps_lifetime', 'max_vps_count'
      )
      expect(environment_config).not_to have_key('default')
    end

    it 'denies normal user showing another user config' do
      as(user) { json_get show_path(other_user.id, other_user_cfg_env.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows admin to show any user config and includes default' do
      as(admin) { json_get show_path(other_user.id, other_user_cfg_env.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(environment_config['id']).to eq(other_user_cfg_env.id)
      expect(environment_config).to have_key('default')
    end

    it 'returns 404 for unknown config as admin' do
      missing = EnvironmentUserConfig.maximum(:id).to_i + 100

      as(admin) { json_get show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown config as user' do
      missing = EnvironmentUserConfig.maximum(:id).to_i + 100

      as(user) { json_get show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated updates' do
      json_put update_path(user.id, user_cfg_env.id), environment_config: { can_create_vps: true }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal user updates' do
      as(user) do
        json_put update_path(user.id, user_cfg_env.id), environment_config: { can_create_vps: true }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'rejects support updates' do
      as(support) do
        json_put update_path(user.id, user_cfg_env.id), environment_config: { can_create_vps: true }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin update of explicit values' do
      user_cfg_env.update!(
        default: true,
        can_create_vps: false,
        can_destroy_vps: false,
        vps_lifetime: 0,
        max_vps_count: 1
      )

      as(admin) do
        json_put update_path(user.id, user_cfg_env.id), environment_config: {
          can_create_vps: true,
          max_vps_count: 5
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(environment_config['can_create_vps']).to be(true)
      expect(environment_config['max_vps_count']).to eq(5)
      expect(environment_config['default']).to be(false)

      user_cfg_env.reload
      expect(user_cfg_env.can_create_vps).to be(true)
      expect(user_cfg_env.max_vps_count).to eq(5)
      expect(user_cfg_env.default).to be(false)
    end

    it 'allows admin to reset config to environment defaults' do
      env.update!(
        can_create_vps: true,
        can_destroy_vps: true,
        vps_lifetime: 123,
        max_vps_count: 10
      )

      user_cfg_env.update!(
        default: false,
        can_create_vps: false,
        can_destroy_vps: false,
        vps_lifetime: 1,
        max_vps_count: 2
      )

      as(admin) do
        json_put update_path(user.id, user_cfg_env.id), environment_config: { default: true }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(environment_config['default']).to be(true)
      expect(environment_config['can_create_vps']).to be(true)
      expect(environment_config['can_destroy_vps']).to be(true)
      expect(environment_config['vps_lifetime']).to eq(123)
      expect(environment_config['max_vps_count']).to eq(10)

      user_cfg_env.reload
      expect(user_cfg_env.default).to be(true)
      expect(user_cfg_env.can_create_vps).to be(true)
      expect(user_cfg_env.can_destroy_vps).to be(true)
      expect(user_cfg_env.vps_lifetime).to eq(123)
      expect(user_cfg_env.max_vps_count).to eq(10)
    end

    it 'returns validation error for empty payload' do
      as(admin) { json_put update_path(user.id, user_cfg_env.id), environment_config: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('provide at least one parameter to update')
    end

    it 'rejects invalid parameter types' do
      as(admin) do
        json_put update_path(user.id, user_cfg_env.id), environment_config: { max_vps_count: 'nope' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('max_vps_count')
    end

    it 'returns 404 for unknown config' do
      missing = EnvironmentUserConfig.maximum(:id).to_i + 100

      as(admin) do
        json_put update_path(user.id, missing), environment_config: { can_create_vps: true }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
