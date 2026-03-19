# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Send do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_same_pool_pair!(role: :primary)
    pool = create_pool!(node: SpecSeed.node, role: role)
    src_dataset, src = create_dataset_with_pool!(user: user, pool: pool, name: "src-#{SecureRandom.hex(4)}")
    dst_dataset, dst = create_dataset_with_pool!(user: user, pool: pool, name: "dst-#{SecureRandom.hex(4)}")

    [src_dataset, src, dst_dataset, dst]
  end

  it 'plans initial local sends as a full send followed by an incremental remainder' do
    src_dataset, src, _, dst = create_same_pool_pair!
    port = reserve_test_port!(node: src.pool.node)

    _, snap1 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-1')
    _, snap2 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-2')
    _, snap3 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-3')

    chain, = described_class.fire(port, src, dst, [snap1, snap2, snap3], nil, nil, true)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::LocalSend,
                                      Transactions::Storage::LocalSend
                                    ])
    expect(tx_payloads(chain).map { |payload| payload.fetch('snapshots').map { |snap| snap.fetch('name') } }).to eq([
                                                                                                                      ['snap-1'],
                                                                                                                      %w[snap-1 snap-2 snap-3]
                                                                                                                    ])
    expect(
      transactions_for(chain).map do |tx|
        confirmations_for(chain).where(transaction_id: tx.id).count
      end
    ).to eq([1, 2])
    expect(
      SnapshotInPool.where(dataset_in_pool: dst).order(:snapshot_id).pluck(:snapshot_id)
    ).to eq([snap1.snapshot_id, snap2.snapshot_id, snap3.snapshot_id])
  end

  it 'plans initial remote sends as recv/send/recv_check pairs' do
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dst_pool = create_pool!(node: SpecSeed.other_node, role: :primary)
    src_dataset, src = create_dataset_with_pool!(user: user, pool: src_pool, name: "src-#{SecureRandom.hex(4)}")
    _, dst = create_dataset_with_pool!(user: user, pool: dst_pool, name: "dst-#{SecureRandom.hex(4)}")
    port = reserve_test_port!(node: dst_pool.node)

    _, snap1 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-1')
    _, snap2 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-2')
    _, snap3 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-3')

    chain, = described_class.fire(port, src, dst, [snap1, snap2, snap3], nil, nil, true)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck,
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck
                                    ])
    expect(
      transactions_for(chain).map do |tx|
        confirmations_for(chain).where(transaction_id: tx.id).count
      end
    ).to eq([0, 0, 1, 0, 0, 2])
  end

  it 'creates confirmations only for snapshots after the common base on incremental sends' do
    src_dataset, src, _, dst = create_same_pool_pair!
    port = reserve_test_port!(node: src.pool.node)

    _, snap1 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-1')
    _, snap2 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-2')
    _, snap3 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-3')

    chain, = described_class.fire(port, src, dst, [snap1, snap2, snap3], nil, nil, false)

    expect(tx_classes(chain)).to eq([Transactions::Storage::LocalSend])
    expect(
      SnapshotInPool.where(dataset_in_pool: dst).order(:snapshot_id).pluck(:snapshot_id)
    ).to eq([snap2.snapshot_id, snap3.snapshot_id])
    expect(confirmations_for(chain).count).to eq(2)
  end

  it 'creates backup SnapshotInPool rows and branch entries for backup destinations' do
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dst_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    dataset, src = create_dataset_with_pool!(user: user, pool: src_pool, name: "src-#{SecureRandom.hex(4)}")
    dst = attach_dataset_to_pool!(dataset: dataset, pool: dst_pool)
    tree = create_tree!(dip: dst, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'backup-head', head: true)
    port = reserve_test_port!(node: dst_pool.node)

    _, snap1 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')
    _, snap2 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-2')

    chain, = described_class.fire(port, src, dst, [snap1, snap2], nil, branch, true)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck,
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck
                                    ])
    expect(
      SnapshotInPool.where(dataset_in_pool: dst).order(:snapshot_id).pluck(:snapshot_id)
    ).to eq([snap1.snapshot_id, snap2.snapshot_id])
    expect(
      SnapshotInPoolInBranch.joins(:snapshot_in_pool)
                            .where(snapshot_in_pools: { dataset_in_pool_id: dst.id })
                            .order(:snapshot_in_pool_id)
                            .pluck(:branch_id)
    ).to eq([branch.id, branch.id])
  end

  it 'uses local sends between different pools on the same node' do
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dst_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, src = create_dataset_with_pool!(user: user, pool: src_pool, name: "src-#{SecureRandom.hex(4)}")
    dst = attach_dataset_to_pool!(dataset: dataset, pool: dst_pool)
    tree = create_tree!(dip: dst, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'backup-head', head: true)
    port = reserve_test_port!(node: dst_pool.node)

    _, snap1 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')
    _, snap2 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-2')

    chain, = described_class.fire(port, src, dst, [snap1, snap2], nil, branch, true)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::LocalSend,
                                      Transactions::Storage::LocalSend
                                    ])
    expect(
      SnapshotInPool.where(dataset_in_pool: dst).order(:snapshot_id).pluck(:snapshot_id)
    ).to eq([snap1.snapshot_id, snap2.snapshot_id])
    expect(
      SnapshotInPoolInBranch.joins(:snapshot_in_pool)
                            .where(snapshot_in_pools: { dataset_in_pool_id: dst.id })
                            .order(:snapshot_in_pool_id)
                            .pluck(:branch_id)
    ).to eq([branch.id, branch.id])
  end

  it 'propagates rollback dataset suffix through local sends on the same node' do
    src_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dst_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, src = create_dataset_with_pool!(user: user, pool: src_pool, name: "src-#{SecureRandom.hex(4)}")
    dst = attach_dataset_to_pool!(dataset: dataset, pool: dst_pool)
    port = reserve_test_port!(node: dst_pool.node)

    _, snap1 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')

    chain, = described_class.fire(port, src, dst, [snap1], nil, nil, true, :rollback)

    expect(tx_classes(chain)).to eq([Transactions::Storage::LocalSend])
    expect(tx_payloads(chain).first.fetch('dst_dataset_name')).to end_with('.rollback')
  end

  it 'wraps send planning with queue reservations when requested' do
    src_dataset, src, _, dst = create_same_pool_pair!
    port = reserve_test_port!(node: src.pool.node)

    _, snap1 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-1')
    _, snap2 = create_snapshot!(dataset: src_dataset, dip: src, name: 'snap-2')

    chain, = described_class.fire(
      port,
      src,
      dst,
      [snap1, snap2],
      nil,
      nil,
      true,
      nil,
      send_reservation: true
    )

    expect(tx_classes(chain)).to eq([
                                      Transactions::Queue::Reserve,
                                      Transactions::Queue::Reserve,
                                      Transactions::Storage::LocalSend,
                                      Transactions::Storage::LocalSend,
                                      Transactions::Queue::Release,
                                      Transactions::Queue::Release
                                    ])
  end
end
