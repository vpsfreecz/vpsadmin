# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe DatasetAction, :no_transaction do
  let(:fixture) { {} }

  def connection_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context do |session|
          block.call
        ensure
          session.destroy!
        end
      end
    end
  end

  before do
    unlock_transaction_signer!
    connection_thread do
      pool = create_pool!(node: SpecSeed.node, role: :primary)
      backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
      dataset, source, target = create_dataset_pair!(user: SpecSeed.user, pool: pool, backup_pool: backup_pool)
      _, env = create_daily_backup_env_plan!(environment: pool.node.location.environment)
      source.add_plan(env)
      fixture.merge!(pool: pool, backup_pool: backup_pool, dataset: dataset, source: source, target: target, env: env)
    end.value
  end

  after do
    connection_thread do
      sources = fixture.values_at(:source, :target).compact
      actions = described_class.where(pool_id: fixture[:pool]&.id)
                               .or(described_class.where(src_dataset_in_pool_id: sources.map(&:id)))
      RepeatableTask.where(class_name: 'DatasetAction', row_id: actions.select(:id)).delete_all
      GroupSnapshot.where(dataset_action_id: actions.select(:id)).delete_all
      actions.delete_all
      DatasetInPoolPlan.where(dataset_in_pool_id: sources.map(&:id)).delete_all
      ResourceLock.where(resource: 'DatasetInPool', row_id: sources.map(&:id)).delete_all
      sources.each { |source| source.dataset_properties.delete_all }
      fixture[:dataset]&.dataset_properties&.delete_all
      DatasetInPool.where(id: sources.map(&:id)).delete_all
      Dataset.where(id: fixture[:dataset]&.id).delete_all
      [fixture[:pool], fixture[:backup_pool]].compact.each do |pool|
        pool.dataset_properties.delete_all
        pool.delete
      end
      fixture.each_value do |record|
        PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).delete_all
      end
    end.value
  end

  %i[backup group_snapshot].each do |kind|
    it "skips a loaded #{kind} after plan removal under read committed" do
      ready = Queue.new
      resume = Queue.new
      worker = connection_thread do
        TransactionChain.transaction(isolation: :read_committed) do
          source = DatasetInPool.find(fixture[:source].id)
          stale = if kind == :backup
                    source.src_dataset_actions.first!
                  else
                    source.group_snapshots.first!.dataset_action
                  end
          # The scheduler may already have loaded both its action and members.
          members = stale.group_snapshots.map(&:dataset_in_pool) if kind == :group_snapshot
          ready << true
          resume.pop
          result = if kind == :backup
                     stale.execute
                   else
                     TransactionChains::Dataset::GroupSnapshot.fire(members, expected_action: stale.id)
                   end
          expect(result.first).to be_nil
          expect(source.snapshot_in_pools.count).to eq(0)
          raise ActiveRecord::Rollback
        end
      end
      Timeout.timeout(10) { ready.pop }
      connection_thread do
        VpsAdmin::API::DatasetPlans.with_locked_source(fixture[:dataset]) do |source|
          source.del_plan(source.dataset_in_pool_plans.first!)
        end
      end.value
      resume << true
      Timeout.timeout(20) { worker.value }
    ensure
      resume << true if resume
      worker&.join(25) || worker&.kill&.join
    end
  end

  it 'skips a removed member from a loaded group while snapshotting its current member' do
    connection_thread do
      TransactionChain.transaction(isolation: :read_committed) do
        source = DatasetInPool.find(fixture[:source].id)
        other_dataset, other_source = create_dataset_with_pool!(
          user: source.dataset.user, pool: source.pool, name: "remaining-#{SecureRandom.hex(4)}"
        )
        attach_dataset_to_pool!(dataset: other_dataset, pool: fixture[:backup_pool])
        other_source.add_plan(fixture[:env])
        action = source.group_snapshots.first!.dataset_action
        members = action.group_snapshots.map(&:dataset_in_pool)
        expect(members.map(&:id)).to contain_exactly(source.id, other_source.id)
        source.del_plan(source.dataset_in_pool_plans.first!)

        chain, prepared = TransactionChains::Dataset::GroupSnapshot.fire(members, expected_action: action.id)

        expect(chain).to be_queued
        expect(tx_classes(chain)).to eq([Transactions::Storage::CreateSnapshots])
        expect(prepared.map(&:dataset_in_pool_id)).to eq([other_source.id])
        expect(source.snapshot_in_pools.count).to eq(0)
        expect(Snapshot.where(dataset_id: source.dataset_id).count).to eq(0)
        expect(other_source.snapshot_in_pools.first!.confirmed).to eq(:confirm_create)
        expect(Snapshot.where(dataset_id: other_dataset.id).first!.confirmed).to eq(:confirm_create)
        expect(action.reload.group_snapshots.pluck(:dataset_in_pool_id)).to eq([other_source.id])
        raise ActiveRecord::Rollback
      end
    end.value
  end

  it 'rejects concurrent plan mutation while disablement holds its source lock' do
    lock = fixture[:source].acquire_lock
    worker = connection_thread do
      expect do
        VpsAdmin::API::DatasetPlans.with_locked_source(fixture[:dataset]) { raise 'must not mutate' }
      end.to raise_error(ResourceLocked)
    end
    Timeout.timeout(10) { worker.value }
  ensure
    lock&.release
    worker&.join(15) || worker&.kill&.join
  end
end
