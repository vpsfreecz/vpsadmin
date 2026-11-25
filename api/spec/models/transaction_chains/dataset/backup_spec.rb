# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Backup do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  it 'executes a current plan backup with transfer and both rotations under query caching' do
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dst_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: dst_pool.node)
    dataset, src, dst = create_dataset_pair!(user: user, pool: src_pool, backup_pool: dst_pool)
    [src, dst].each { |dip| dip.update!(min_snapshots: 1, max_snapshots: 1, snapshot_max_age: 0) }
    oldest_snapshot, oldest_source_copy = create_snapshot!(dataset: dataset, dip: src, name: 'scheduled-1')
    create_snapshot!(dataset: dataset, dip: src, name: 'scheduled-2')
    create_snapshot!(dataset: dataset, dip: src, name: 'scheduled-3')
    _, environment_plan = create_daily_backup_env_plan!(environment: src_pool.node.location.environment)
    assignment = src.add_plan(environment_plan)

    ActiveRecord::Base.cache do
      action = DatasetAction.find_by!(dataset_in_pool_plan: assignment, action: :backup)
      chain, = action.execute
      classes = tx_classes(chain)
      destroy_indexes = classes.each_index.select { |index| classes[index] == Transactions::Storage::DestroySnapshot }

      expect(chain).to be_a(described_class)
      expect(chain).to be_queued
      expect(classes).to include(
        Transactions::Storage::Send, Transactions::Storage::Recv,
        Transactions::Storage::RecvCheck, Transactions::Storage::DestroySnapshot
      )
      expect(classes.index(Transactions::Storage::Send)).to be < destroy_indexes.first
      expect(classes.index(Transactions::Storage::RecvCheck)).to be < destroy_indexes.first
      expect(destroy_indexes.map { |index| tx_payloads(chain)[index].fetch('pool_fs') }).to include(
        src_pool.filesystem, dst_pool.filesystem
      )
      expect(oldest_source_copy.reload.confirmed).to eq(:confirm_destroy)
      expect(dst.snapshot_in_pools.find_by!(snapshot: oldest_snapshot).confirmed).to eq(:confirm_destroy)
    end
  end

  it 'runs transfer before source and destination rotation' do
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dst_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: dst_pool.node)

    dataset, src, dst = create_dataset_pair!(
      user: user,
      pool: src_pool,
      backup_pool: dst_pool,
      name: "backup-#{SecureRandom.hex(4)}"
    )

    src.update!(min_snapshots: 1, max_snapshots: 1, snapshot_max_age: 0)
    dst.update!(min_snapshots: 1, max_snapshots: 1, snapshot_max_age: 0)

    oldest_snapshot, = create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')
    create_snapshot!(dataset: dataset, dip: src, name: 'snap-2')
    create_snapshot!(dataset: dataset, dip: src, name: 'snap-3')

    chain, = described_class.fire(src, dst)

    destroy_indexes = tx_classes(chain).each_index.select do |idx|
      tx_classes(chain)[idx] == Transactions::Storage::DestroySnapshot
    end

    expect(tx_classes(chain)).to include(
      Transactions::Storage::Send,
      Transactions::Storage::Recv,
      Transactions::Storage::RecvCheck,
      Transactions::Storage::DestroySnapshot
    )
    expect(destroy_indexes).not_to be_empty
    expect(tx_classes(chain).index(Transactions::Storage::Send)).to be < destroy_indexes.first
    expect(tx_classes(chain).index(Transactions::Storage::RecvCheck)).to be < destroy_indexes.first
    expect(oldest_snapshot.reload.confirmed).to eq(:confirm_destroy)

    expect do
      TransactionChains::Dataset::FullDownload.fire(
        oldest_snapshot,
        format: :archive,
        send_mail: false
      )
    end.to raise_error(ResourceLocked) { |error|
      expect(error.get_lock.locked_by).to eq(chain)
    }
  end

  it 'locks both source and destination dataset in pool records' do
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dst_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: dst_pool.node)

    dataset, src, dst = create_dataset_pair!(
      user: user,
      pool: src_pool,
      backup_pool: dst_pool,
      name: "backup-#{SecureRandom.hex(4)}"
    )

    create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')

    chain, = described_class.fire(src, dst)

    locked_rows = chain.locks.select { |lock| lock.resource == 'DatasetInPool' }.map(&:row_id)

    expect(locked_rows).to include(src.id, dst.id)
  end

  it 'sets affect concerns for the source dataset' do
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dst_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: dst_pool.node)

    dataset, src, dst = create_dataset_pair!(
      user: user,
      pool: src_pool,
      backup_pool: dst_pool,
      name: "backup-#{SecureRandom.hex(4)}"
    )

    create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')

    chain, = described_class.fire(src, dst)

    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Dataset', dataset.id])
  end
end
