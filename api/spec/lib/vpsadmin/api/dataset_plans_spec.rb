# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe VpsAdmin::API::DatasetPlans do
  let(:user) { SpecSeed.user }
  let(:pool) { SpecSeed.pool }

  around do |example|
    plans = VpsAdmin::API::DatasetPlans::Registrator.plans.dup
    example.run
  ensure
    VpsAdmin::API::DatasetPlans::Registrator.instance_variable_set(:@plans, plans)
  end

  def create_dataset_fixture!(name: "spec-dataset-#{SecureRandom.hex(4)}")
    create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: name
    )
  end

  def create_backup_dip!(dataset)
    backup_pool = Pool.new(
      node: SpecSeed.other_node,
      label: 'Spec Backup Pool',
      filesystem: "spec_backup_#{SecureRandom.hex(4)}",
      role: :backup,
      is_open: true
    )
    backup_pool.save!

    DatasetInPool.create!(
      dataset: dataset,
      pool: backup_pool,
      label: 'backup',
      confirmed: DatasetInPool.confirmed(:confirmed)
    )
  end

  def register_plan!(dataset_in_pool, &block)
    plan_name = :"spec_plan_#{SecureRandom.hex(4)}"
    plan, = build_dataset_plan_fixture!(
      dataset_in_pool: dataset_in_pool,
      plan_name: plan_name,
      &block
    )
    plan
  end

  def group_snapshot_action(plan, dip)
    DatasetAction.find_by!(
      pool: dip.pool,
      action: DatasetAction.actions[:group_snapshot],
      dataset_plan: plan.dataset_plan
    )
  end

  def confirmation_recorder
    calls = []
    recorder = Object.new
    recorder.define_singleton_method(:calls) { calls }
    recorder.define_singleton_method(:just_create) do |record|
      calls << [:just_create, record.class.name, record.id]
    end
    recorder.define_singleton_method(:just_destroy) do |record|
      calls << [:just_destroy, record.class.name, record.id]
    end
    recorder
  end

  it 'registers a plan for a dataset in pool' do
    _, dip = create_dataset_fixture!
    plan = register_plan!(dip) do |target|
      group_snapshot target, '00', '03', '*', '*', '*'
    end

    expect do
      plan.register(dip)
    end.to change(DatasetInPoolPlan, :count).by(1)

    expect(
      DatasetInPoolPlan.where(dataset_in_pool: dip, environment_dataset_plan: EnvironmentDatasetPlan.last)
    ).to exist
  end

  it 'creates group-snapshot action, repeatable task, and group snapshot' do
    _, dip = create_dataset_fixture!
    plan = register_plan!(dip) do |target|
      group_snapshot target, '00', '03', '*', '*', '*'
    end

    plan.register(dip)

    action = group_snapshot_action(plan, dip)
    task = RepeatableTask.find_for!(action)
    snapshot = GroupSnapshot.find_by!(dataset_in_pool: dip, dataset_action: action)

    expect(action.action).to eq('group_snapshot')
    expect(task.hour).to eq('03')
    expect(snapshot.dataset_in_pool).to eq(dip)
  end

  it 'unregisters a group-snapshot plan and removes its side effects' do
    _, dip = create_dataset_fixture!
    plan = register_plan!(dip) do |target|
      group_snapshot target, '00', '03', '*', '*', '*'
    end
    dip_plan = plan.register(dip)
    action = group_snapshot_action(plan, dip)
    task = RepeatableTask.find_for!(action)
    snapshot = GroupSnapshot.find_by!(dataset_in_pool: dip, dataset_action: action)

    plan.unregister(dip)

    expect(DatasetInPoolPlan.exists?(dip_plan.id)).to be(false)
    expect(GroupSnapshot.exists?(snapshot.id)).to be(false)
    expect(RepeatableTask.exists?(task.id)).to be(false)
    expect(DatasetAction.exists?(action.id)).to be(false)
  end

  it 'creates a backup action and repeatable task on an open backup dataset' do
    dataset, dip = create_dataset_fixture!
    backup_dip = create_backup_dip!(dataset)
    plan = register_plan!(dip) do |target|
      backup target, '22', '02', '*', '*', '*'
    end

    dip_plan = plan.register(dip)
    action = DatasetAction.find_by!(
      src_dataset_in_pool: dip,
      dst_dataset_in_pool: backup_dip,
      dataset_in_pool_plan: dip_plan,
      action: DatasetAction.actions[:backup]
    )
    task = RepeatableTask.find_for!(action)

    expect(action.action).to eq('backup')
    expect(task.hour).to eq('02')
  end

  it 'records confirmation operations instead of immediately destroying rows' do
    _, dip = create_dataset_fixture!
    confirmation = confirmation_recorder
    plan = register_plan!(dip) do |target|
      group_snapshot target, '00', '03', '*', '*', '*'
    end

    dip_plan = plan.register(dip, confirmation: confirmation)
    action = group_snapshot_action(plan, dip)
    task = RepeatableTask.find_for!(action)
    snapshot = GroupSnapshot.find_by!(dataset_in_pool: dip, dataset_action: action)

    expect(confirmation.calls).to include(
      [:just_create, 'DatasetInPoolPlan', dip_plan.id],
      [:just_create, 'DatasetAction', action.id],
      [:just_create, 'RepeatableTask', task.id],
      [:just_create, 'GroupSnapshot', snapshot.id]
    )

    plan.unregister(dip, confirmation: confirmation)

    expect(confirmation.calls).to include(
      [:just_destroy, 'GroupSnapshot', snapshot.id],
      [:just_destroy, 'RepeatableTask', task.id],
      [:just_destroy, 'DatasetAction', action.id],
      [:just_destroy, 'DatasetInPoolPlan', dip_plan.id]
    )
    expect(DatasetInPoolPlan.exists?(dip_plan.id)).to be(true)
    expect(GroupSnapshot.exists?(snapshot.id)).to be(true)
    expect(RepeatableTask.exists?(task.id)).to be(true)
    expect(DatasetAction.exists?(action.id)).to be(true)
  end

  it 'raises when a plan is not enabled in the dataset environment' do
    _, dip = create_dataset_fixture!
    plan_name = :"spec_missing_plan_#{SecureRandom.hex(4)}"

    VpsAdmin::API::DatasetPlans::Registrator.plan(
      plan_name,
      label: 'Spec Missing Plan'
    ) do |target|
      group_snapshot target, '00', '03', '*', '*', '*'
    end
    plan = VpsAdmin::API::DatasetPlans::Registrator.plans.fetch(plan_name)

    expect do
      plan.env_dataset_plan(dip)
    end.to raise_error(VpsAdmin::API::Exceptions::DatasetPlanNotInEnvironment) { |error|
      expect(error.dataset_plan).to eq(plan.dataset_plan)
      expect(error.environment).to eq(dip.pool.node.location.environment)
    }
  end
end
