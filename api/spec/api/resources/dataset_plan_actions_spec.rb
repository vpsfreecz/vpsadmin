# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Dataset plan actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    backup_dip
  end

  let(:pool) do
    SpecSeed.pool.tap do |p|
      p.update!(role: Pool.roles[:primary], refquota_check: false)
    end
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }

  let!(:dataset_data) do
    create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "plan-root-#{SecureRandom.hex(4)}"
    )
  end

  let(:dataset) { dataset_data.first }
  let(:dip) { dataset_data.last }

  let!(:backup_pool) do
    Pool.new(
      node: pool.node,
      label: "Backup Pool #{SecureRandom.hex(3)}",
      filesystem: "backup_pool_#{SecureRandom.hex(3)}",
      role: :backup,
      is_open: true
    ).tap(&:save!)
  end

  let(:backup_dip) do
    DatasetInPool.create!(
      dataset: dataset,
      pool: backup_pool,
      confirmed: DatasetInPool.confirmed(:confirmed)
    )
  end

  def plans_path(dataset_id)
    vpath("/datasets/#{dataset_id}/plans")
  end

  def plan_path(dataset_id, plan_id)
    vpath("/datasets/#{dataset_id}/plans/#{plan_id}")
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

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def plans
    json.dig('response', 'plans') || json.dig('response', 'dataset_in_pool_plans') || []
  end

  def plan_obj
    json.dig('response', 'plan') || json.dig('response', 'dataset_in_pool_plan')
  end

  def response_message
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_plan_for_dataset(env_plan)
    dip.add_plan(env_plan)
  end

  def as_token(user)
    session = create_open_session!(user:, auth_type: 'token', token_lifetime: 'permanent')
    header 'X-HaveAPI-Auth-Token', session.token.token
    yield
  ensure
    header 'X-HaveAPI-Auth-Token', nil
  end

  def plan_metadata_counts
    [DatasetInPoolPlan.count, GroupSnapshot.count, DatasetAction.count, RepeatableTask.count]
  end

  def enabled_plan
    create_daily_backup_env_plan!(environment: pool.node.location.environment,
                                  user_add: true, user_remove: true).last
  end

  def pending_plan_confirmation!(membership)
    with_current_context(user:) do |session|
      chain = TransactionChain.create!(name: 'spec_plan', type: 'TransactionChain', state: :queued,
                                       size: 0, progress: 0, user:, user_session: session, urgent_rollback: false)
      transaction = Transactions::Utils::NoOp.fire_chained(chain, nil, args: [pool.node_id], urgent: false)
      TransactionConfirmation.create!(parent_transaction: transaction, class_name: membership.class.name,
                                      table_name: membership.class.table_name, row_pks: { 'id' => membership.id },
                                      confirm_type: :just_destroy_type)
    end
  end

  describe 'Common mutation guards' do
    it 'refuses direct enrollment while storage is frozen without changing metadata' do
      env_plan = enabled_plan
      before = plan_metadata_counts
      StorageFreezeControl.singleton!.update_columns(mode: 1)

      as_token(user) { json_post plans_path(dataset.id), plan: { environment_dataset_plan: env_plan.id } }

      expect_status(423)
      expect(json['status']).to be(false)
      expect(plan_metadata_counts).to eq(before)
    end

    it 'refuses direct removal while storage is frozen without changing metadata' do
      membership = create_plan_for_dataset(enabled_plan)
      before = plan_metadata_counts
      StorageFreezeControl.singleton!.update_columns(mode: 1)

      as_token(user) { json_delete plan_path(dataset.id, membership.id) }

      expect_status(423)
      expect(json['status']).to be(false)
      expect(plan_metadata_counts).to eq(before)
    end

    it 'refuses direct enrollment of a locked source without changing metadata' do
      env_plan = enabled_plan
      before = plan_metadata_counts
      dataset.acquire_lock

      as_token(user) { json_post plans_path(dataset.id), plan: { environment_dataset_plan: env_plan.id } }

      expect_status(423)
      expect(json['status']).to be(false)
      expect(plan_metadata_counts).to eq(before)
    end

    it 'refuses direct removal of a locked source without changing metadata' do
      membership = create_plan_for_dataset(enabled_plan)
      before = plan_metadata_counts
      dip.acquire_lock

      as_token(user) { json_delete plan_path(dataset.id, membership.id) }

      expect_status(423)
      expect(json['status']).to be(false)
      expect(plan_metadata_counts).to eq(before)
    end

    it 'refuses pending removal without requiring a source lock' do
      membership = create_plan_for_dataset(enabled_plan)
      pending_plan_confirmation!(membership)
      before = plan_metadata_counts
      expect(dip.get_current_lock).to be_nil

      as_token(user) { json_delete plan_path(dataset.id, membership.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('pending confirmation')
      expect(plan_metadata_counts).to eq(before)
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get plans_path(dataset.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to list own plans' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      plan = create_plan_for_dataset(env_plan)

      as(user) { json_get plans_path(dataset.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = plans.map { |row| row['id'] }
      expect(ids).to include(plan.id)
    end

    it 'returns 404 for other users' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      create_plan_for_dataset(env_plan)

      as(other_user) { json_get plans_path(dataset.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list plans' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      plan = create_plan_for_dataset(env_plan)

      as(SpecSeed.admin) { json_get plans_path(dataset.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = plans.map { |row| row['id'] }
      expect(ids).to include(plan.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      plan = create_plan_for_dataset(env_plan)
      json_get plan_path(dataset.id, plan.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show own plan' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      plan = create_plan_for_dataset(env_plan)

      as(user) { json_get plan_path(dataset.id, plan.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(plan_obj['id']).to eq(plan.id)
    end

    it 'returns 404 for other users' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      plan = create_plan_for_dataset(env_plan)

      as(other_user) { json_get plan_path(dataset.id, plan.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show plan' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      plan = create_plan_for_dataset(env_plan)

      as(SpecSeed.admin) { json_get plan_path(dataset.id, plan.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(plan_obj['id']).to eq(plan.id)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )

      json_post plans_path(dataset.id), plan: { environment_dataset_plan: env_plan.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to assign plan when permitted' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )

      expect do
        as(user) { json_post plans_path(dataset.id), plan: { environment_dataset_plan: env_plan.id } }
      end.to change { DatasetInPoolPlan.where(dataset_in_pool: dip).count }.by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'denies user when user_add is false' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: false,
        user_remove: true
      )

      as(user) { json_post plans_path(dataset.id), plan: { environment_dataset_plan: env_plan.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/insufficient permission/i)
    end

    it 'rejects user_add permission borrowed from another environment' do
      _, target_env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: false,
        user_remove: true
      )
      _, other_env_plan = create_daily_backup_env_plan!(
        environment: SpecSeed.other_environment,
        user_add: true,
        user_remove: true
      )

      expect do
        as(user) { json_post plans_path(dataset.id), plan: { environment_dataset_plan: other_env_plan.id } }
      end.not_to(change { DatasetInPoolPlan.where(dataset_in_pool: dip).count })

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('dataset environment')
      expect(DatasetInPoolPlan.where(dataset_in_pool: dip, environment_dataset_plan: target_env_plan)).to be_empty
    end

    it 'allows admin to assign regardless of user_add' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: false,
        user_remove: true
      )

      as(SpecSeed.admin) { json_post plans_path(dataset.id), plan: { environment_dataset_plan: env_plan.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(DatasetInPoolPlan.where(dataset_in_pool: dip).count).to eq(1)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      plan = create_plan_for_dataset(env_plan)

      json_delete plan_path(dataset.id, plan.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'denies user when user_remove is false' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: false
      )
      plan = create_plan_for_dataset(env_plan)

      as(user) { json_delete plan_path(dataset.id, plan.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/insufficient permission/i)
    end

    it 'allows user to delete plan when permitted' do
      _, env_plan = create_daily_backup_env_plan!(
        environment: pool.node.location.environment,
        user_add: true,
        user_remove: true
      )
      plan = create_plan_for_dataset(env_plan)
      action = DatasetAction.find_by!(
        dataset_in_pool_plan: plan,
        action: DatasetAction.actions[:backup]
      )
      task = RepeatableTask.find_for!(action)

      as(user) { json_delete plan_path(dataset.id, plan.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(DatasetInPoolPlan.exists?(id: plan.id)).to be(false)
      expect(DatasetAction.exists?(id: action.id)).to be(false)
      expect(RepeatableTask.exists?(id: task.id)).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
