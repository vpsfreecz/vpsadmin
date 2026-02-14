# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Environment::DatasetPlan' do
  let(:fixtures) do
    environment = SpecSeed.environment
    other_environment = SpecSeed.other_environment
    admin = SpecSeed.admin
    user = SpecSeed.user
    support = SpecSeed.support
    ds_plan = DatasetPlan.find_or_create_by!(name: 'daily_backup')

    env_plan_addable = EnvironmentDatasetPlan.create!(
      environment: environment,
      dataset_plan: ds_plan,
      user_add: true,
      user_remove: true
    )

    env_plan_not_addable = EnvironmentDatasetPlan.create!(
      environment: environment,
      dataset_plan: ds_plan,
      user_add: false,
      user_remove: false
    )

    other_env_plan_addable = EnvironmentDatasetPlan.create!(
      environment: other_environment,
      dataset_plan: ds_plan,
      user_add: true,
      user_remove: true
    )

    {
      environment: environment,
      other_environment: other_environment,
      admin: admin,
      user: user,
      support: support,
      ds_plan: ds_plan,
      env_plan_addable: env_plan_addable,
      env_plan_not_addable: env_plan_not_addable,
      other_env_plan_addable: other_env_plan_addable
    }
  end

  before do
    header 'Accept', 'application/json'
  end

  def environment
    fixtures.fetch(:environment)
  end

  def other_environment
    fixtures.fetch(:other_environment)
  end

  def admin
    fixtures.fetch(:admin)
  end

  def user
    fixtures.fetch(:user)
  end

  def support
    fixtures.fetch(:support)
  end

  def ds_plan
    fixtures.fetch(:ds_plan)
  end

  def env_plan_addable
    fixtures.fetch(:env_plan_addable)
  end

  def env_plan_not_addable
    fixtures.fetch(:env_plan_not_addable)
  end

  def other_env_plan_addable
    fixtures.fetch(:other_env_plan_addable)
  end

  def index_path(env_id)
    vpath("/environments/#{env_id}/dataset_plans")
  end

  def show_path(env_id, env_plan_id)
    vpath("/environments/#{env_id}/dataset_plans/#{env_plan_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def plans
    json.dig('response', 'dataset_plans')
  end

  def plan
    json.dig('response', 'dataset_plan')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  describe 'API description' do
    it 'includes environment.dataset_plan scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('environment.dataset_plan#index', 'environment.dataset_plan#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(environment.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'restricts users to addable plans for the environment' do
      as(user) { json_get index_path(environment.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(plans).to be_an(Array)

      ids = plans.map { |row| row['id'] }
      expect(ids).to contain_exactly(env_plan_addable.id)

      row = plans.find { |item| item['id'] == env_plan_addable.id }
      expect(row).to include('id', 'label', 'dataset_plan', 'user_add', 'user_remove')
      expect(row['user_add']).to be(true)
      expect(row['user_remove']).to eq(env_plan_addable.user_remove)
      expect(rid(row['dataset_plan']).to_i).to eq(ds_plan.id)

      if row['dataset_plan'].is_a?(Hash)
        expect(row['dataset_plan']).to include('label' => ds_plan.label)
      end
    end

    it 'restricts support to addable plans for the environment' do
      as(support) { json_get index_path(environment.id) }

      expect_status(200)
      ids = plans.map { |row| row['id'] }
      expect(ids).to contain_exactly(env_plan_addable.id)
    end

    it 'allows admins to see all plans for the environment' do
      as(admin) { json_get index_path(environment.id) }

      expect_status(200)
      ids = plans.map { |row| row['id'] }
      expect(ids).to include(env_plan_addable.id, env_plan_not_addable.id)
      expect(ids).not_to include(other_env_plan_addable.id)
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path(environment.id), dataset_plan: { limit: 1 } }

      expect_status(200)
      expect(plans.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = env_plan_addable.id
      as(admin) { json_get index_path(environment.id), dataset_plan: { from_id: boundary } }

      expect_status(200)
      ids = plans.map { |row| row['id'] }
      expect(ids).to all(be > boundary)

      if env_plan_not_addable.id > boundary
        expect(ids).to include(env_plan_not_addable.id)
      end
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get index_path(environment.id), _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(2)

      as(user) { json_get index_path(environment.id), _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(1)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(environment.id, env_plan_addable.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show addable plans' do
      as(user) { json_get show_path(environment.id, env_plan_addable.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(plan['id']).to eq(env_plan_addable.id)
      expect(plan['user_add']).to be(true)
      expect(rid(plan['dataset_plan']).to_i).to eq(ds_plan.id)
    end

    it 'allows users to show non-addable plans' do
      as(user) { json_get show_path(environment.id, env_plan_not_addable.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(plan['user_add']).to be(false)
    end

    it 'returns 404 for wrong environment' do
      as(user) { json_get show_path(other_environment.id, env_plan_addable.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown plan' do
      missing = EnvironmentDatasetPlan.maximum(:id).to_i + 100
      as(admin) { json_get show_path(environment.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
