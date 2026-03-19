# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::SnapshotInPool::Destroy do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  it 'destroys the Snapshot row when the last live SnapshotInPool is removed' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "snap-destroy-#{SecureRandom.hex(4)}")
    snap, sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')

    chain, = described_class.fire(sip)

    expect(sip.reload.confirmed).to eq(:confirm_destroy)
    expect(tx_classes(chain)).to eq(
      [
        Transactions::Utils::NoOp,
        Transactions::Storage::DestroySnapshot
      ]
    )
    expect(confirmations_for(chain).map(&:class_name)).to include('SnapshotInPool', 'Snapshot')
    expect(snap.reload.name).to eq('snap-1')
  end

  it 'keeps the Snapshot row when another live SnapshotInPool still references it' do
    pool_a = create_pool!(node: SpecSeed.node, role: :primary)
    pool_b = create_pool!(node: SpecSeed.other_node, role: :backup)
    dataset, dip_a = create_dataset_with_pool!(user: user, pool: pool_a, name: "snap-destroy-#{SecureRandom.hex(4)}")
    dip_b = attach_dataset_to_pool!(dataset: dataset, pool: pool_b)
    snap, sip = create_snapshot!(dataset: dataset, dip: dip_a, name: 'snap-1')
    mirror_snapshot!(snapshot: snap, dip: dip_b)

    chain, = described_class.fire(sip)

    expect(sip.reload.confirmed).to eq(:confirm_destroy)
    expect(confirmations_for(chain).map(&:class_name)).to include('SnapshotInPool')
    expect(confirmations_for(chain).map(&:class_name)).not_to include('Snapshot')
  end

  it 'destroys empty branches and trees when the last branched snapshot is removed' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "snap-destroy-#{SecureRandom.hex(4)}")
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)
    _, sip = create_snapshot!(dataset: dataset, dip: backup, name: 'snap-1')
    entry = attach_snapshot_to_branch!(sip: sip, branch: branch)

    chain, = described_class.fire(entry)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::Utils::NoOp,
        Transactions::Storage::DestroySnapshot,
        Transactions::Storage::DestroyBranch,
        Transactions::Storage::DestroyTree
      ]
    )
    expect(entry.reload.confirmed).to eq(:confirm_destroy)
    expect(sip.reload.confirmed).to eq(:confirm_destroy)
    expect(branch.reload.confirmed).to eq(:confirm_destroy)
    expect(tree.reload.confirmed).to eq(:confirm_destroy)
  end

  it 'nullifies SnapshotDownload references before destroying the snapshot' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "snap-destroy-#{SecureRandom.hex(4)}")
    snap, sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')

    SnapshotDownload.create!(
      user: user,
      pool: pool,
      snapshot: snap,
      from_snapshot: snap,
      secret_key: SecureRandom.hex(8),
      file_name: 'snapshot.bin',
      confirmed: SnapshotDownload.confirmed(:confirmed),
      format: :archive,
      object_state: :active
    )

    chain, = described_class.fire(sip)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::Utils::NoOp,
        Transactions::Storage::DestroySnapshot
      ]
    )

    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'SnapshotDownload' && row.confirm_type == 'edit_after_type'
    end

    expect(confirmation).to be_present
    expect(confirmation.attr_changes).to eq('snapshot_id' => nil)
  end

  it 'decrements the parent snapshot reference_count when destroying a dependent branch entry' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "snap-destroy-#{SecureRandom.hex(4)}")
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    parent_snap, parent_sip = create_snapshot!(dataset: dataset, dip: backup, name: 'snap-1')
    parent_sip.update!(reference_count: 1)
    parent_entry = attach_snapshot_to_branch!(sip: parent_sip, branch: branch)

    child_snap, child_sip = create_snapshot!(dataset: dataset, dip: backup, name: 'snap-2')
    child_entry = attach_snapshot_to_branch!(
      sip: child_sip,
      branch: branch,
      parent_entry: parent_entry
    )

    chain, = described_class.fire(child_entry)

    decrement_rows = confirmations_for(chain).select { |row| row.confirm_type == 'decrement_type' }

    expect(tx_classes(chain)).to eq(
      [
        Transactions::Utils::NoOp,
        Transactions::Storage::DestroySnapshot
      ]
    )
    expect(parent_snap.reload.name).to eq('snap-1')
    expect(child_snap.reload.name).to eq('snap-2')
    expect(decrement_rows.map(&:row_pks)).to include('id' => parent_sip.id)
    expect(decrement_rows.map(&:row_pks)).not_to include('id' => child_sip.id)
  end
end
