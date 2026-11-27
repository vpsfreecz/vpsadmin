require 'spec_helper'
require 'timeout'

RSpec.describe VpsAdmin::API::Operations::Dataset::RemoveSnapshots, :no_transaction do
  let!(:pool) { create_pool!(node: SpecSeed.node, role: :primary) }
  let!(:fixture) { create_dataset_with_pool!(user: SpecSeed.user, pool: pool, name: "preview-#{SecureRandom.hex(4)}") }
  let(:dataset) { fixture[0] }
  let(:source) { fixture[1] }

  after do
    snapshot_ids = Snapshot.where(dataset: dataset).pluck(:id)
    SnapshotInPool.where(snapshot_id: snapshot_ids).delete_all
    Snapshot.where(id: snapshot_ids).delete_all
    property_ids = DatasetProperty.where(dataset_in_pool: source).pluck(:id)
    DatasetPropertyHistory.where(dataset_property_id: property_ids).delete_all
    DatasetProperty.where(id: property_ids).delete_all
    DatasetProperty.where(pool: pool).delete_all
    DatasetInPool.where(id: source.id).delete_all
    Dataset.where(id: dataset.id).delete_all
    Pool.where(id: pool.id).delete_all
  end

  it 'runs a real read-only repeatable-read preview without a task or resource lock' do
    before = [TransactionChain.count, Transaction.count, ResourceLock.count]
    inventory = described_class.new.preview(dataset)
    expect(inventory[:manifest][:counts]).to include(datasets: 1, snapshots: 0)
    expect([TransactionChain.count, Transaction.count, ResourceLock.count]).to eq(before)
    operation = described_class.new
    allow(operation).to receive(:inventory) { Dataset.where(id: dataset.id).update_all(name: 'must-not-write') }
    expect { operation.preview(dataset) }.to raise_error(ActiveRecord::StatementInvalid, /READ ONLY|read.only/i)
    expect(dataset.reload.name).to start_with('preview-')
  end

  it 'keeps one snapshot view when a writer commits before later inventory reads' do
    ready = Queue.new
    resume = Queue.new
    operation = described_class.new
    allow(operation).to receive(:load_history!).and_wrap_original do |method|
      ready << true
      Timeout.timeout(10) { resume.pop }
      method.call
    end
    # load_history! is read twice to check identity; synchronize each read.
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { operation.preview(Dataset.find(dataset.id)) }
    end
    Timeout.timeout(10) { ready.pop }
    create_snapshot!(dataset: dataset, dip: source, name: 'committed-during-preview')
    resume << true
    Timeout.timeout(10) { ready.pop }
    resume << true
    inventory = Timeout.timeout(10) { worker.value }
    expect(inventory[:manifest][:snapshot_locations]).to be_empty
    expect(source.snapshot_in_pools.count).to eq(1)
  ensure
    2.times { resume << true } if resume
    worker&.join(15) || worker&.kill&.join
  end

  it 'rejects a stale review using current reads even inside an older repeatable-read transaction' do
    digest = described_class.new.preview(dataset)[:manifest_digest]
    ready = Queue.new
    resume = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context do |session|
          TransactionChain.transaction(isolation: :repeatable_read) do
            stale = Dataset.find(dataset.id)
            stale.dataset_in_pools.to_a
            SnapshotInPool.where(dataset_in_pool_id: source.id).to_a
            ready << true
            Timeout.timeout(10) { resume.pop }
            expect { described_class.run(stale, manifest_digest: digest) }.to raise_error(described_class::StalePreview)
            expect(ResourceLock.where(resource: 'DatasetInPool', row_id: source.id)).not_to exist
            raise ActiveRecord::Rollback
          end
          session.delete
        end
      end
    end
    Timeout.timeout(10) { ready.pop }
    create_snapshot!(dataset: dataset, dip: source, name: 'committed-before-lock')
    resume << true
    Timeout.timeout(15) { worker.value }
    expect(source.snapshot_in_pools.first.confirmed).to eq(:confirmed)
  ensure
    resume << true if resume
    worker&.join(15) || worker&.kill&.join
  end

  it 'excludes scheduler, plan, clone, transfer and child creation on other connections until the task closes' do
    target_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    target = attach_dataset_to_pool!(dataset:, pool: target_pool)
    _, sip = create_snapshot!(dataset:, dip: source)
    userns_map = create_user_namespace_map!(user: dataset.user)
    chain = nil
    with_current_context do |session|
      digest = described_class.new.preview(dataset).fetch(:manifest_digest)
      chain, = described_class.run(dataset, manifest_digest: digest)
      session.delete
    end
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context do |session|
          operations = [
            -> { TransactionChains::Dataset::Snapshot.fire(source) },
            -> { TransactionChains::Dataset::Backup.fire(source, target) },
            -> { TransactionChains::Dataset::Transfer.fire(source, target) },
            -> { TransactionChains::SnapshotInPool::UseClone.fire(sip, userns_map) },
            -> { TransactionChains::Dataset::Create.fire(pool, source, [Dataset.new(name: 'locked-child')], {}) },
            -> { VpsAdmin::API::DatasetPlans.with_locked_source(dataset) { raise 'must not mutate' } }
          ]
          operations.each { |operation| expect(&operation).to raise_error(ResourceLocked) }
          queued, = TransactionChains::Dataset::GroupSnapshot.fire([source])
          expect(queued).to be_nil
          session.delete
        end
      end
    end
    Timeout.timeout(15) { worker.value }
    expect(source.snapshot_in_pools.count).to eq(1)
    expect(dataset.reload.children).to be_empty
    expect(target.reload.confirmed).to eq(:confirmed)
  ensure
    worker&.join(15) || worker&.kill&.join
    if chain
      transactions = Transaction.where(transaction_chain_id: chain.id)
      TransactionConfirmation.where(transaction_id: transactions.select(:id)).delete_all
      transactions.delete_all
      chain.transaction_chain_concerns.delete_all
      ResourceLock.where(locked_by: chain).delete_all
      chain.delete
    end
    if target
      DatasetProperty.where(dataset_in_pool: target).delete_all
      target.delete
      DatasetProperty.where(pool: target_pool).delete_all
      target_pool.delete
    end
    if userns_map
      userns = userns_map.user_namespace
      userns_map.delete
      userns.delete
    end
  end
end
