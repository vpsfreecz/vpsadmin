# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::VpsMigration do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  def create_plan_with_vpses!(count:, concurrency: 1, state: :running, stop_on_error: false)
    fixture = create_vps_migration_fixture!(count: count)
    plan = create_migration_plan!(
      dst_node: fixture.fetch(:dst_node),
      state: state,
      concurrency: concurrency,
      stop_on_error: stop_on_error
    )

    migrations = fixture.fetch(:vpses).map do |vps|
      build_vps_migration!(
        plan: plan,
        vps: vps,
        transaction_chain: build_active_chain!
      )
    end

    [plan, migrations]
  end

  def run_plan(plan)
    task.send(:run_plan, plan)
  end

  it 'marks finished running migrations done when their chain is done' do
    plan, migrations = create_plan_with_vpses!(count: 1)
    migration = migrations.first
    migration.update!(state: :running, transaction_chain: build_active_chain!(state: :done))

    run_plan(plan)

    expect(migration.reload.state).to eq('done')
    expect(migration.finished_at).to be_present
    expect(plan.reload.state).to eq('done')
  end

  %i[rollbacking failed fatal resolved].each do |chain_state|
    it "marks finished running migrations error when their chain is #{chain_state}" do
      plan, migrations = create_plan_with_vpses!(count: 1)
      migration = migrations.first
      migration.update!(state: :running, transaction_chain: build_active_chain!(state: chain_state))

      run_plan(plan)

      expect(migration.reload.state).to eq('error')
      expect(migration.finished_at).to be_present
    end
  end

  it 'moves a plan with stop_on_error to failing while other migrations are still running' do
    plan, migrations = create_plan_with_vpses!(count: 2, stop_on_error: true)
    migrations.first.update!(state: :running, transaction_chain: build_active_chain!(state: :failed))
    migrations.last.update!(state: :running, transaction_chain: build_active_chain!(state: :queued))

    run_plan(plan)

    expect(migrations.first.reload.state).to eq('error')
    expect(migrations.last.reload.state).to eq('running')
    expect(plan.reload.state).to eq('failing')
  end

  it 'schedules only up to concurrency minus currently running migrations' do
    plan, migrations = create_plan_with_vpses!(count: 3, concurrency: 2)
    migrations.first.update!(state: :running, transaction_chain: build_active_chain!(state: :queued))
    scheduled = []

    allow(task).to receive(:migrate_vps) do |migration, _plan, _locks|
      scheduled << migration.id
      migration.update!(
        state: :running,
        started_at: Time.now,
        transaction_chain: build_active_chain!
      )
    end

    run_plan(plan)

    expect(scheduled).to eq([migrations.second.id])
    expect(migrations.first.reload.state).to eq('running')
    expect(migrations.second.reload.state).to eq('running')
    expect(migrations.third.reload.state).to eq('queued')
  end

  it 'preserves plan mail options when scheduling queued migrations' do
    plan, migrations = create_plan_with_vpses!(count: 1)
    plan.update!(send_mail: false, reason: 'node evacuation')
    migration = migrations.first
    chain = build_active_chain!
    chain_builder = class_double(TransactionChains::Vps::Migrate::OsToOs)
    captured_args = nil

    allow(TransactionChains::Vps::Migrate).to receive(:chain_for)
      .with(migration.vps, plan.node)
      .and_return(chain_builder)
    allow(chain_builder).to receive(:fire2) do |args:, locks:|
      captured_args = args
      expect(locks).to eq(plan.resource_locks.to_a)
      [chain, nil]
    end

    run_plan(plan)

    expect(captured_args.last).to include(
      send_mail: false,
      reason: 'node evacuation'
    )
    expect(migration.reload.transaction_chain).to eq(chain)
  end

  {
    cancelling: 'cancelled',
    failing: 'error'
  }.each do |plan_state, final_state|
    it "finishes #{plan_state} plans with no remaining work as #{final_state}" do
      plan, migrations = create_plan_with_vpses!(count: 1, state: plan_state)
      migrations.first.update!(state: :cancelled)

      run_plan(plan)

      expect(plan.reload.state).to eq(final_state)
      expect(plan.finished_at).to be_present
    end
  end

  it 'cancels queued migrations whose VPS was deleted' do
    plan, migrations = create_plan_with_vpses!(count: 1)
    migration = migrations.first
    migration.update_column(:vps_id, Vps.maximum(:id).to_i + 10_000)

    run_plan(plan)

    expect(migration.reload.state).to eq('cancelled')
  end

  it 'cancels queued migrations whose VPS moved away from the source node' do
    plan, migrations = create_plan_with_vpses!(count: 1)
    migration = migrations.first
    migration.vps.update!(node: plan.node)

    run_plan(plan)

    expect(migration.reload.state).to eq('cancelled')
  end

  it 'keeps migrations queued when their resources are locked' do
    plan, migrations = create_plan_with_vpses!(count: 1)
    migration = migrations.first

    allow(task).to receive(:migrate_vps).and_raise(ResourceLocked.new(migration.vps, 'locked'))

    run_plan(plan)

    expect(migration.reload.state).to eq('queued')
  end
end
