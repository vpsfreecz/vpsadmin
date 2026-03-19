# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Rollback do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_primary_with_backup!
    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: backup_pool.node)
    create_port_reservations!(node: primary_pool.node)

    create_dataset_pair!(
      user: user,
      pool: primary_pool,
      backup_pool: backup_pool,
      name: "rollback-#{SecureRandom.hex(4)}"
    )
  end

  it 'rolls back locally and marks newer local snapshots for destroy when there are no backups' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "local-#{SecureRandom.hex(4)}")
    snap1, = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')
    newer_snap, newer_sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-2')

    chain, = described_class.fire(dip, snap1)

    expect(tx_classes(chain)).to eq([Transactions::Storage::Rollback])
    expect(newer_sip.reload.confirmed).to eq(:confirm_destroy)
    expect(newer_snap.reload.confirmed).to eq(:confirm_destroy)
  end

  it 'raises SnapshotInUse when a newer local snapshot is still referenced' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "local-#{SecureRandom.hex(4)}")
    snap1, = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')
    _, newer_sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-2')
    newer_sip.update!(reference_count: 1)

    expect do
      described_class.fire(dip, snap1)
    end.to raise_error(VpsAdmin::API::Exceptions::SnapshotInUse)
  end

  it 'plans only a local rollback when the target snapshot is already the latest one' do
    dataset, primary, backup = create_primary_with_backup!
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    snap1, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-1')
    snap2, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-2')
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: backup), branch: branch)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap2, dip: backup), branch: branch)

    chain, = described_class.fire(primary, snap2)

    expect(tx_classes(chain)).to eq([Transactions::Storage::Rollback])
    expect(backup.dataset_trees.count).to eq(1)
    expect(branch.reload.head).to be(true)
  end

  it 'creates a new backup head branch when rolling back below the old tip' do
    dataset, primary, backup = create_primary_with_backup!
    tree = create_tree!(dip: backup, index: 0, head: true)
    old_branch = create_branch!(tree: tree, name: 'head', head: true)

    snap1, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-1')
    snap2, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-2')
    snap3, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-3')

    backup_sip1 = mirror_snapshot!(snapshot: snap1, dip: backup)
    entry1 = attach_snapshot_to_branch!(sip: backup_sip1, branch: old_branch)
    backup_sip2 = mirror_snapshot!(snapshot: snap2, dip: backup)
    entry2 = attach_snapshot_to_branch!(sip: backup_sip2, branch: old_branch)
    backup_sip3 = mirror_snapshot!(snapshot: snap3, dip: backup)
    entry3 = attach_snapshot_to_branch!(sip: backup_sip3, branch: old_branch)

    old_history_id = dataset.current_history_id

    chain, = described_class.fire(primary, snap2)

    new_branch = backup.reload.dataset_trees.take!.branches.where(name: snap2.name).order(:id).last

    expect(tx_classes(chain)).to include(
      Transactions::Storage::Rollback,
      Transactions::Storage::BranchDataset
    )
    expect(backup.reload.dataset_trees.take!.branches.count).to eq(2)
    expect(new_branch).to be_present
    expect(new_branch.id).not_to eq(old_branch.id)
    expect(new_branch.name).to eq(snap2.name)
    expect(backup_sip3.reload.snapshot_id).to eq(snap3.id)

    expect(confirmations_for(chain).map { |row| [row.class_name, row.row_pks, row.attr_changes] }).to include(
      ['Branch', { 'id' => old_branch.id }, { 'head' => 0 }],
      ['Dataset', { 'id' => dataset.id }, { 'current_history_id' => old_history_id + 1 }],
      ['SnapshotInPoolInBranch', { 'id' => entry1.id }, { 'branch_id' => new_branch.id }],
      ['SnapshotInPoolInBranch', { 'id' => entry2.id }, { 'branch_id' => new_branch.id }],
      ['SnapshotInPoolInBranch', { 'id' => entry3.id }, { 'snapshot_in_pool_in_branch_id' => entry2.id }],
      ['Snapshot', { 'id' => snap1.id }, { 'history_id' => old_history_id + 1 }],
      ['Snapshot', { 'id' => snap2.id }, { 'history_id' => old_history_id + 1 }]
    )

    increment_rows = confirmations_for(chain).select do |row|
      row.class_name == 'SnapshotInPool' &&
        row.row_pks == { 'id' => backup_sip2.id } &&
        row.confirm_type == 'increment_type'
    end

    expect(increment_rows.count).to eq(1)
  end

  it 'restores a snapshot available only on backup through prepare/apply rollback and branching' do
    dataset, primary, backup = create_primary_with_backup!
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    snap1, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-1')
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: backup), branch: branch)

    snap2 = Snapshot.create!(
      dataset: dataset,
      name: 'snap-2',
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(:confirmed)
    )
    backup_sip2 = mirror_snapshot!(snapshot: snap2, dip: backup)
    entry2 = attach_snapshot_to_branch!(sip: backup_sip2, branch: branch)

    snap3 = Snapshot.create!(
      dataset: dataset,
      name: 'snap-3',
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(:confirmed)
    )
    attach_snapshot_to_branch!(
      sip: mirror_snapshot!(snapshot: snap3, dip: backup),
      branch: branch,
      parent_entry: entry2
    )

    chain, = described_class.fire(primary, snap2)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::PrepareRollback,
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck,
                                      Transactions::Storage::ApplyRollback,
                                      Transactions::Storage::BranchDataset
                                    ])
  end

  it 'moves the backup head without creating a new branch when the rollback target is already a branch tip' do
    dataset, primary, backup = create_primary_with_backup!
    tree = create_tree!(dip: backup, index: 0, head: true)
    target_branch = create_branch!(tree: tree, name: 'target-tip', head: false)
    current_head = create_branch!(tree: tree, name: 'current-head', index: 1, head: true)

    snap1, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-1')
    snap2, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-2')
    create_snapshot!(dataset: dataset, dip: primary, name: 'snap-3')

    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: backup), branch: target_branch)
    entry2 = attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap2, dip: backup), branch: target_branch)

    snap3 = Snapshot.create!(
      dataset: dataset,
      name: 'backup-head-only',
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(:confirmed)
    )
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap3, dip: backup), branch: current_head)

    chain, = described_class.fire(primary, snap2)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::Rollback,
                                      Transactions::Utils::NoOp
                                    ])
    expect(backup.reload.dataset_trees.take!.branches.count).to eq(2)
    expect(confirmations_for(chain).map { |row| [row.class_name, row.row_pks, row.attr_changes] }).to include(
      ['Branch', { 'id' => current_head.id }, { 'head' => 0 }],
      ['Branch', { 'id' => target_branch.id }, { 'head' => 1 }]
    )
    expect(entry2.reload.branch_id).to eq(target_branch.id)
  end
end
