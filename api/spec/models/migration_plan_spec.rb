# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MigrationPlan do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:chain_class) { class_double(TransactionChains::Vps::Migrate::OsToOs) }

  def create_plan_with_migrations!(count:, concurrency: 1, state: :staged, send_mail: false)
    fixture = create_vps_migration_fixture!(count: count)
    plan = create_migration_plan!(
      dst_node: fixture.fetch(:dst_node),
      state: state,
      concurrency: concurrency,
      send_mail: send_mail
    )

    migrations = fixture.fetch(:vpses).each_with_index.map do |vps, index|
      build_vps_migration!(
        plan: plan,
        vps: vps,
        created_at: Time.utc(2026, 1, 1, 0, 0, index)
      )
    end

    [plan, migrations]
  end

  def stub_migration_chain!(locked_vps_ids: [])
    successful_vps_ids = []
    attempted_vps_ids = []

    allow(TransactionChains::Vps::Migrate).to receive(:chain_for).and_return(chain_class)
    allow(chain_class).to receive(:fire2) do |args:, **|
      vps = args.fetch(0)
      attempted_vps_ids << vps.id
      raise ResourceLocked.new(vps, 'locked') if locked_vps_ids.include?(vps.id)

      successful_vps_ids << vps.id
      [build_active_chain!, nil]
    end

    [attempted_vps_ids, successful_vps_ids]
  end

  describe '#start!' do
    it 'starts up to concurrency migrations in creation order' do
      plan, migrations = create_plan_with_migrations!(count: 3, concurrency: 2)
      _attempted, successful = stub_migration_chain!

      plan.start!

      expect(plan.reload.state).to eq('running')
      expect(successful).to eq(migrations.first(2).map(&:vps_id))
      expect(migrations.first(2).map { |m| m.reload.state }).to all(eq('running'))
      expect(migrations.first(2).map { |m| m.reload.started_at }).to all(be_present)
      expect(migrations.first(2).map { |m| m.reload.transaction_chain }).to all(be_present)
      expect(migrations.last.reload.state).to eq('queued')
      expect(migrations.last.started_at).to be_nil
    end

    it 'continues after ResourceLocked and starts later migrations' do
      plan, migrations = create_plan_with_migrations!(count: 3, concurrency: 2)
      attempted, successful = stub_migration_chain!(locked_vps_ids: [migrations.first.vps_id])

      plan.start!

      expect(attempted).to eq(migrations.map(&:vps_id))
      expect(successful).to eq(migrations.last(2).map(&:vps_id))
      expect(migrations.first.reload.state).to eq('queued')
      expect(migrations.last(2).map { |m| m.reload.state }).to all(eq('running'))
      expect(plan.reload.state).to eq('running')
    end

    it 'sends migration-plan mail when enabled' do
      plan, = create_plan_with_migrations!(count: 1, send_mail: true)
      stub_migration_chain!
      allow(TransactionChains::MigrationPlan::Mail).to receive(:fire)

      plan.start!

      expect(TransactionChains::MigrationPlan::Mail).to have_received(:fire).with(plan).once
    end

    it 'does not send migration-plan mail when disabled' do
      plan, = create_plan_with_migrations!(count: 1, send_mail: false)
      stub_migration_chain!
      allow(TransactionChains::MigrationPlan::Mail).to receive(:fire)

      plan.start!

      expect(TransactionChains::MigrationPlan::Mail).not_to have_received(:fire)
    end
  end

  describe '#cancel!' do
    it 'cancels queued migrations and leaves running migrations running' do
      plan, migrations = create_plan_with_migrations!(count: 2, state: :running)
      migrations.last.update!(state: :running, transaction_chain: build_active_chain!)

      plan.cancel!

      expect(plan.reload.state).to eq('cancelling')
      expect(migrations.first.reload.state).to eq('cancelled')
      expect(migrations.last.reload.state).to eq('running')
    end
  end

  describe '#fail!' do
    it 'cancels queued migrations and leaves running migrations running' do
      plan, migrations = create_plan_with_migrations!(count: 2, state: :running)
      migrations.last.update!(state: :running, transaction_chain: build_active_chain!)

      plan.fail!

      expect(plan.reload.state).to eq('failing')
      expect(migrations.first.reload.state).to eq('cancelled')
      expect(migrations.last.reload.state).to eq('running')
    end
  end

  describe '#finish!' do
    {
      running: 'done',
      cancelling: 'cancelled',
      failing: 'error'
    }.each do |initial_state, expected_state|
      it "finishes #{initial_state} plans as #{expected_state}" do
        plan = create_migration_plan!(
          dst_node: create_vps_migration_fixture!(count: 1).fetch(:dst_node),
          state: initial_state
        )
        SpecSeed.node.acquire_lock(plan)

        plan.finish!

        expect(plan.reload.state).to eq(expected_state)
        expect(plan.finished_at).to be_present
        expect(plan.resource_locks).to be_empty
      end
    end

    it 'respects an explicit final state' do
      plan = create_migration_plan!(
        dst_node: create_vps_migration_fixture!(count: 1).fetch(:dst_node),
        state: :running
      )

      plan.finish!(:cancelled)

      expect(plan.reload.state).to eq('cancelled')
      expect(plan.finished_at).to be_present
    end
  end
end
