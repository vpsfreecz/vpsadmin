# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'timeout'

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

  def register_plan!(dataset_in_pool, keep_empty_group_snapshots: false, &block)
    plan_name = :"spec_plan_#{SecureRandom.hex(4)}"
    described_class::Registrator.plan(plan_name, label: 'Spec plan', keep_empty_group_snapshots:, &block)
    plan = described_class.plans.fetch(plan_name)
    EnvironmentDatasetPlan.create!(environment: dataset_in_pool.pool.node.location.environment,
                                   dataset_plan: plan.dataset_plan, user_add: true, user_remove: true)
    plan
  end

  def create_group_template!(plan, dip, minute: '*/5', hour: '*')
    plan.with_configuration_lock do
      action = DatasetAction.create!(pool: dip.pool, dataset_plan: plan.dataset_plan, action: :group_snapshot)
      task = RepeatableTask.create!(class_name: 'DatasetAction', table_name: 'dataset_actions', row_id: action.id,
                                    minute:, hour:, day_of_month: '*', month: '*', day_of_week: '*')
      [action, task]
    end
  end

  def create_chain!
    with_current_context(user:) do |session|
      TransactionChain.create!(name: 'spec_plan', type: 'TransactionChain', state: :queued, size: 0, progress: 0,
                               user:, user_session: session, urgent_rollback: false)
    end
  end

  def pending_confirmation!(record, chain:, type: :just_destroy_type)
    transaction = Transactions::Utils::NoOp.fire_chained(chain, nil, args: [pool.node_id], urgent: false)
    TransactionConfirmation.create!(parent_transaction: transaction, class_name: record.class.name,
                                    table_name: record.class.table_name, row_pks: { 'id' => record.id }, confirm_type: type)
  end

  def retained_plan!(dip)
    register_plan!(dip, keep_empty_group_snapshots: true) do |target|
      group_snapshot target, '*/5', '*', '*', '*', '*'
    end
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

  [false, true].each do |retained|
    mode = retained ? 'retained' : 'legacy'

    it "enrolls, reuses and removes numeric group schedules for a #{mode} plan" do
      _, dip = create_dataset_fixture!
      _, second = create_dataset_fixture!
      plan = register_plan!(dip, keep_empty_group_snapshots: retained) do |target|
        group_snapshot target, 15, 6, '*', '*', '*'
      end
      create_group_template!(plan, dip, minute: 15, hour: 6) if retained

      membership = plan.register(dip)
      action = group_snapshot_action(plan, dip)
      task = RepeatableTask.find_for!(action)
      expect(task.reload.attributes.values_at('minute', 'hour', 'day_of_month', 'month', 'day_of_week'))
        .to eq(['15', '6', '*', '*', '*'])
      expect(plan.register(dip)).to eq(membership) if retained
      second_membership = plan.register(second)
      expect(action.group_snapshots.pluck(:dataset_in_pool_id)).to contain_exactly(dip.id, second.id)
      expect(RepeatableTask.find_for!(action).id).to eq(task.id)

      plan.unregister(dip)
      expect(DatasetInPoolPlan.exists?(membership.id)).to be(false)
      expect(action.group_snapshots.pluck(:dataset_in_pool_id)).to eq([second.id])
      expect(RepeatableTask.find_for!(action).id).to eq(task.id)
      plan.unregister(second)
      expect(DatasetInPoolPlan.exists?(second_membership.id)).to be(false)
      expect(GroupSnapshot.where(dataset_action: action)).to be_empty
      expect(DatasetAction.exists?(action.id)).to be(retained)
      expect(RepeatableTask.exists?(task.id)).to be(retained)
    end

    it "enrolls and removes numeric backup schedules for a #{mode} plan" do
      dataset, dip = create_dataset_fixture!
      destination = create_backup_dip!(dataset)
      plan = register_plan!(dip, keep_empty_group_snapshots: retained) do |target|
        backup target, 22, 2, 4, 5, 6
      end

      membership = plan.register(dip)
      action = membership.dataset_actions.sole
      task = RepeatableTask.find_for!(action)
      expect(action.dst_dataset_in_pool_id).to eq(destination.id)
      expect(task.reload.attributes.values_at('minute', 'hour', 'day_of_month', 'month', 'day_of_week'))
        .to eq(%w[22 2 4 5 6])
      if retained
        expect(plan.register(dip)).to eq(membership)
        expect(membership.dataset_actions.reload).to contain_exactly(action)
        expect(RepeatableTask.find_for!(action).id).to eq(task.id)
      end

      plan.unregister(dip)
      expect(DatasetInPoolPlan.exists?(membership.id)).to be(false)
      expect(DatasetAction.exists?(action.id)).to be(false)
      expect(RepeatableTask.exists?(task.id)).to be(false)
    end
  end

  it 'retains the exact shared action and task when its last member is removed' do
    _, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    action, task = create_group_template!(plan, dip)
    confirmation = confirmation_recorder
    membership = plan.register(dip, confirmation:)
    plan.unregister(dip, confirmation:)

    expect(DatasetAction.find(action.id)).to eq(action)
    expect(RepeatableTask.find(task.id)).to eq(task)
    expect(confirmation.calls).to include([:just_create, 'DatasetInPoolPlan', membership.id])
    expect(confirmation.calls.select { |_, model, _| %w[DatasetAction RepeatableTask].include?(model) }).to be_empty

    plan.unregister(dip)
    expect(action.group_snapshots).to be_empty
    expect(DatasetInPoolPlan.exists?(membership.id)).to be(false)
    expect(RepeatableTask.exists?(task.id)).to be(true)
  end

  it 'refuses to enroll into a missing shared template without provisional rows' do
    _, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    before = [DatasetInPoolPlan.count, GroupSnapshot.count, DatasetAction.count, RepeatableTask.count]

    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /template is missing/)
    expect([DatasetInPoolPlan.count, GroupSnapshot.count, DatasetAction.count, RepeatableTask.count]).to eq(before)
  end

  it 'refuses incompatible and duplicate template tasks' do
    _, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    _, task = create_group_template!(plan, dip, minute: '*/10')

    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /incompatible schedule/)
    task.update!(minute: '*/5')
    task.dup.save!
    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /ambiguous/)
    expect(DatasetInPoolPlan.where(dataset_in_pool: dip)).to be_empty
  end

  it 'preserves unique group membership and refuses ambiguous environment definitions' do
    _, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    action, = create_group_template!(plan, dip)
    membership = plan.register(dip)
    member = action.group_snapshots.sole
    expect { member.dup.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(action.group_snapshots.reload).to contain_exactly(member)
    expect(plan.register(dip)).to eq(membership)

    plan.env_dataset_plan(dip).dup.save!
    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /environment.*ambiguous/i)
    expect(action.group_snapshots.reload).to contain_exactly(member)
    expect(DatasetInPoolPlan.find(membership.id)).to eq(membership)
  end

  it 'validates repeat enrollment including the exact existing backup destination' do
    dataset, dip = create_dataset_fixture!
    destination = create_backup_dip!(dataset)
    plan = register_plan!(dip, keep_empty_group_snapshots: true) do |target|
      group_snapshot target, '*/5', '*', '*', '*', '*'
      backup target, '2-59/10', '*', '*', '*', '*'
    end
    create_group_template!(plan, dip)
    membership = plan.register(dip)
    before = [DatasetInPoolPlan.count, GroupSnapshot.count, DatasetAction.count, RepeatableTask.count]

    expect(plan.register(dip)).to eq(membership)
    expect([DatasetInPoolPlan.count, GroupSnapshot.count, DatasetAction.count, RepeatableTask.count]).to eq(before)
    action = membership.dataset_actions.sole
    expect(action.dst_dataset_in_pool_id).to eq(destination.id)
    foreign = create_backup_dip!(dataset)
    action.update!(dst_dataset_in_pool: foreign)
    foreign.pool.update!(is_open: false)

    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /conflicting destination/)
    expect([DatasetInPoolPlan.count, GroupSnapshot.count, DatasetAction.count, RepeatableTask.count]).to eq(before)
  end

  it 'rejects multiple eligible backup destinations instead of choosing one' do
    dataset, dip = create_dataset_fixture!
    2.times { create_backup_dip!(dataset) }
    plan = register_plan!(dip, keep_empty_group_snapshots: true) do |target|
      backup target, '2-59/10', '*', '*', '*', '*'
    end

    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /ambiguous/)
    expect(DatasetInPoolPlan.where(dataset_in_pool: dip)).to be_empty
    expect(DatasetAction.where(src_dataset_in_pool: dip)).to be_empty
  end

  it 'preserves the first-open destination policy for a legacy plan with multiple backups' do
    dataset, dip = create_dataset_fixture!
    2.times { create_backup_dip!(dataset) }
    expected = dataset.dataset_in_pools.joins(:pool).where(pools: { role: :backup, is_open: true }).take!
    plan = register_plan!(dip) { |target| backup target, '22', '02', '*', '*', '*' }

    membership = plan.register(dip)

    expect(membership.dataset_actions.sole.dst_dataset_in_pool_id).to eq(expected.id)
    expect(dataset.dataset_in_pools.joins(:pool).where(pools: { role: :backup, is_open: true }).count).to eq(2)
  end

  it 'validates a schedule before committing any plan, group or task rows' do
    _, dip = create_dataset_fixture!
    plan = register_plan!(dip) { |target| group_snapshot target, 'garbage', '*', '*', '*', '*' }

    expect { plan.register(dip) }.to raise_error(VpsAdmin::Scheduler::CronTask::InvalidField)
    expect(DatasetInPoolPlan.where(dataset_in_pool: dip)).to be_empty
    expect(DatasetAction.where(dataset_plan: plan.dataset_plan)).to be_empty
  end

  it 'checks storage admission before enrollment, removal and template provisioning' do
    _, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    create_group_template!(plan, dip)
    membership = plan.register(dip)
    StorageFreezeControl.singleton!.update_columns(mode: 1)

    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::StorageReadOnly)
    expect { plan.unregister(dip) }.to raise_error(VpsAdmin::API::Exceptions::StorageReadOnly)
    expect { plan.with_configuration_lock { raise 'must not reach provisioning' } }
      .to raise_error(VpsAdmin::API::Exceptions::StorageReadOnly)
    expect(DatasetInPoolPlan.exists?(membership.id)).to be(true)
  end

  it 'refuses source locks owned by another chain for both enrollment and removal' do
    _, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    create_group_template!(plan, dip)
    plan.register(dip)
    chain = create_chain!

    [dip.dataset, dip].each do |source|
      lock = source.acquire_lock(chain)
      expect { plan.register(dip) }.to raise_error(ResourceLocked)
      expect { plan.unregister(dip) }.to raise_error(ResourceLocked)
      lock.release
    end
  end

  it 'refuses a pending membership confirmation even when the source lock is absent' do
    _, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    create_group_template!(plan, dip)
    membership = plan.register(dip)
    pending_confirmation!(membership, chain: create_chain!)

    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /pending confirmation/)
    expect { plan.unregister(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /pending confirmation/)
    expect(DatasetInPoolPlan.exists?(membership.id)).to be(true)
  end

  it 'allows repeated and different-DIP enrollment owned by the same outer chain' do
    _, dip = create_dataset_fixture!
    _, second = create_dataset_fixture!
    plan = retained_plan!(dip)
    action, task = create_group_template!(plan, dip)
    chain = create_chain!
    dip.acquire_lock(chain)
    dip.dataset.acquire_lock(chain)
    second.acquire_lock(chain)

    transaction = Transactions::Utils::NoOp.fire_chained(
      chain, nil, args: [pool.node_id], urgent: false, retain_context: true
    ) do |confirmation|
      expect(confirmation.transaction_chain_id).to eq(chain.id)
      expect(confirmation).not_to respond_to(:transaction_chain_id=)
      membership = plan.register(dip, confirmation:)
      expect(plan.register(dip, confirmation:)).to eq(membership)
      plan.register(second, confirmation:)
    end

    expect(action.group_snapshots.count).to eq(2)
    expect(TransactionConfirmation.where(transaction_id: transaction.id).pluck(:table_name))
      .to contain_exactly('dataset_in_pool_plans', 'group_snapshots', 'dataset_in_pool_plans', 'group_snapshots')
    expect(RepeatableTask.exists?(task.id)).to be(true)
    expect { plan.register(dip) }.to raise_error(ResourceLocked)
  end

  it 'allows unconfirmed sources only with current-chain creation ownership' do
    dataset, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    create_group_template!(plan, dip)
    dataset.update!(confirmed: :confirm_create)
    dip.update!(confirmed: :confirm_create)

    expect { plan.register(dip) }.to raise_error(VpsAdmin::API::Exceptions::OperationError, /not confirmed/)
    chain = create_chain!
    Transactions::Utils::NoOp.fire_chained(
      chain, nil, args: [pool.node_id], urgent: false, retain_context: true
    ) do |confirmation|
      confirmation.create(dataset)
      confirmation.create(dip)
      plan.register(dip, confirmation:)
    end

    expect(DatasetInPoolPlan.where(dataset_in_pool: dip).count).to eq(1)
    expect(GroupSnapshot.where(dataset_in_pool: dip).count).to eq(1)
  end

  it 'refuses reuse of a membership pending removal even within its own chain' do
    _, dip = create_dataset_fixture!
    plan = retained_plan!(dip)
    create_group_template!(plan, dip)
    membership = plan.register(dip)
    chain = create_chain!
    transaction = pending_confirmation!(membership, chain:).parent_transaction
    confirmation = Transaction::Confirmable.new(transaction)

    expect { plan.register(dip, confirmation:) }
      .to raise_error(VpsAdmin::API::Exceptions::OperationError, /pending confirmation/)
    expect(DatasetInPoolPlan.where(dataset_in_pool: dip).pluck(:id)).to eq([membership.id])
  end

  it 'serializes last-member removal and concurrent enrollment through the persisted plan', :no_transaction do
    dataset, dip = create_dataset_fixture!
    second_dataset, second = create_dataset_fixture!
    plan = retained_plan!(dip)
    action, task = create_group_template!(plan, dip)
    plan.register(dip)
    ready = Queue.new
    start = Queue.new
    workers = [proc { plan.unregister(dip) }, proc { plan.register(second) }, proc { plan.register(second) }].map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          operation.call
        end
      end
    end
    Timeout.timeout(5) { 3.times { ready.pop } }
    3.times { start << true }
    Timeout.timeout(10) { workers.each(&:value) }

    expect(GroupSnapshot.where(dataset_action: action).pluck(:dataset_in_pool_id)).to eq([second.id])
    expect(DatasetInPoolPlan.where(dataset_in_pool: second).count).to eq(1)
    expect(DatasetAction.where(dataset_plan: plan.dataset_plan).pluck(:id)).to eq([action.id])
    expect(RepeatableTask.find_for!(action).id).to eq(task.id)
  ensure
    3.times { start << true } if start
    workers&.each { |worker| worker.join(10) }
    if plan
      ids = DatasetAction.where(dataset_plan: plan.dataset_plan).pluck(:id)
      GroupSnapshot.where(dataset_action_id: ids).delete_all
      RepeatableTask.where(table_name: 'dataset_actions', row_id: ids).delete_all
      DatasetAction.where(id: ids).delete_all
      DatasetInPoolPlan.where(dataset_in_pool_id: [dip&.id, second&.id].compact).delete_all
      EnvironmentDatasetPlan.where(dataset_plan: plan.dataset_plan).delete_all
      plan.dataset_plan.delete
    end
    [dip, second].compact.each do |copy|
      DatasetProperty.where(dataset_in_pool: copy).delete_all
      copy.delete
    end
    [dataset, second_dataset].compact.each(&:delete)
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
