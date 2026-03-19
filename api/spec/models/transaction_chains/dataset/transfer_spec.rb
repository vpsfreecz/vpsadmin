# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Transfer do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_primary_and_backup!
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: backup_pool.node)

    dataset, src, dst = create_dataset_pair!(
      user: user,
      pool: src_pool,
      backup_pool: backup_pool,
      name: "dataset-#{SecureRandom.hex(4)}"
    )

    [dataset, src, dst]
  end

  it 'creates a head tree and branch on an empty backup destination and plans an initial send' do
    dataset, src, dst = create_primary_and_backup!

    _, snap1 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')
    _, snap2 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-2')
    _, snap3 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-3')

    chain, = described_class.fire(src, dst)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::CreateTree,
                                      Transactions::Storage::BranchDataset,
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck,
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck
                                    ])
    expect(dst.dataset_trees.count).to eq(1)
    expect(head_tree!(dst).head).to be(true)
    expect(head_branch!(dst).head).to be(true)

    send_payloads = transactions_for(chain)
                    .select { |tx| tx.handle == Transactions::Storage::Send.t_type }
                    .map { |tx| JSON.parse(tx.input).dig('input', 'snapshots').map { |snap| snap.fetch('name') } }

    expect(send_payloads).to eq([
                                  ['snap-1'],
                                  %w[snap-1 snap-2 snap-3]
                                ])
    expect(
      SnapshotInPool.where(dataset_in_pool: dst).order(:snapshot_id).pluck(:snapshot_id)
    ).to eq([snap1.snapshot_id, snap2.snapshot_id, snap3.snapshot_id])
  end

  it 'does not plan any transfer when the source has no snapshots' do
    _, src, dst = create_primary_and_backup!

    chain, = use_chain_in_root!(described_class, args: [src, dst])

    expect(chain.transactions).to be_empty
  end

  it 'reuses the head tree and transfers only snapshots after the common base' do
    dataset, src, dst = create_primary_and_backup!
    tree = create_tree!(dip: dst, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'existing-head', head: true)

    snap1, sip1 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')
    snap2, sip2 = create_snapshot!(dataset: dataset, dip: src, name: 'snap-2')
    create_snapshot!(dataset: dataset, dip: src, name: 'snap-3')

    backup_sip1 = mirror_snapshot!(snapshot: snap1, dip: dst)
    attach_snapshot_to_branch!(sip: backup_sip1, branch: branch)
    backup_sip2 = mirror_snapshot!(snapshot: snap2, dip: dst)
    attach_snapshot_to_branch!(sip: backup_sip2, branch: branch)

    chain, = described_class.fire(src, dst)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck
                                    ])
    expect(dst.dataset_trees.count).to eq(1)
    expect(head_tree!(dst).id).to eq(tree.id)
    expect(head_branch!(dst).id).to eq(branch.id)
    expect(
      SnapshotInPool.where(dataset_in_pool: dst).order(:snapshot_id).pluck(:snapshot_id)
    ).to eq([sip1.snapshot_id, sip2.snapshot_id, src.snapshot_in_pools.order(:snapshot_id).last.snapshot_id])
  end

  it 'does not plan any transfer when the backup head is already up to date' do
    dataset, src, dst = create_primary_and_backup!
    tree = create_tree!(dip: dst, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'existing-head', head: true)

    snap1, = create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')
    snap2, = create_snapshot!(dataset: dataset, dip: src, name: 'snap-2')

    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: dst), branch: branch)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap2, dip: dst), branch: branch)

    chain, = use_chain_in_root!(described_class, args: [src, dst])

    expect(chain.transactions).to be_empty
  end

  it 'uses only the backup head branch as the incremental comparison target' do
    dataset, src, dst = create_primary_and_backup!
    head_tree = create_tree!(dip: dst, index: 0, head: true)
    head_branch = create_branch!(tree: head_tree, name: 'current-head', head: true)
    stale_tree = create_tree!(dip: dst, index: 1, head: false)
    stale_branch = create_branch!(tree: stale_tree, name: 'stale-tree', head: true)

    snap1, = create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')
    _, snap2_sip = create_snapshot!(dataset: dataset, dip: src, name: 'snap-2')
    backup_only_snap, backup_only_sip = create_snapshot!(dataset: dataset, dip: dst, name: 'backup-only')

    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: dst), branch: head_branch)
    attach_snapshot_to_branch!(sip: backup_only_sip, branch: stale_branch)

    chain, = described_class.fire(src, dst)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck
                                    ])
    expect(head_tree!(dst).id).to eq(head_tree.id)
    expect(head_branch!(dst).id).to eq(head_branch.id)
    expect(
      SnapshotInPool.where(dataset_in_pool: dst).order(:snapshot_id).pluck(:snapshot_id)
    ).to include(snap2_sip.snapshot_id)
    expect(backup_only_snap.dataset_id).to eq(dataset.id)
  end

  it 'creates a new tree or fails explicitly when source and destination histories diverge' do
    dataset, src, dst = create_primary_and_backup!
    tree = create_tree!(dip: dst, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'existing-head', head: true)

    create_snapshot!(dataset: dataset, dip: src, name: 'src-only')
    backup_snap = Snapshot.create!(
      dataset: dataset,
      name: 'dst-only',
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(:confirmed)
    )
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: backup_snap, dip: dst), branch: branch)

    pending 'history divergence currently only warns and returns without creating a new tree or explicit failure'

    chain, = described_class.fire(src, dst)

    expect(chain.size).to be > 0
    expect(dst.dataset_trees.count).to eq(2)
  end
end
