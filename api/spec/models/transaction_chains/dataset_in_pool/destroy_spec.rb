# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DatasetInPool::Destroy do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  it 'plans snapshot destruction for primary datasets' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "destroy-#{SecureRandom.hex(4)}")
    create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')

    chain, = described_class.fire(dip, recursive: true)

    expect(tx_classes(chain)).to include(
      Transactions::Storage::DestroySnapshot,
      Transactions::Storage::DestroyDataset
    )
    expect(dip.snapshot_in_pools.first.reload.confirmed).to eq(:confirm_destroy)
  end

  it 'plans tree destruction for backup datasets' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "destroy-#{SecureRandom.hex(4)}")
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)
    snap, sip = create_snapshot!(dataset: dataset, dip: backup, name: 'snap-1')
    attach_snapshot_to_branch!(sip: sip, branch: branch)

    chain, = described_class.fire(backup, recursive: true)

    expect(tx_classes(chain)).to include(
      Transactions::Storage::DestroyBranch,
      Transactions::Storage::DestroyTree,
      Transactions::Storage::DestroyDataset
    )
    expect(tree.reload.confirmed).to eq(:confirm_destroy)
    expect(branch.reload.confirmed).to eq(:confirm_destroy)
    expect(snap.reload.name).to eq('snap-1')
  end

  it 'detaches backup heads and sets dataset expiration when only backups remain' do
    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    dataset, primary, backup = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      backup_pool: backup_pool,
      name: "destroy-#{SecureRandom.hex(4)}"
    )
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    chain, = described_class.fire(primary, recursive: true, detach_backups: true)

    expect(dataset.reload.expiration_date).to be_present

    tree_confirmation = confirmations_for(chain).find do |confirmation|
      confirmation.class_name == 'DatasetTree' &&
        confirmation.row_pks == { 'id' => tree.id } &&
        confirmation.attr_changes == { 'head' => 0 }
    end
    branch_confirmation = confirmations_for(chain).find do |confirmation|
      confirmation.class_name == 'Branch' &&
        confirmation.row_pks == { 'id' => branch.id } &&
        confirmation.attr_changes == { 'head' => 0 }
    end

    expect(tree_confirmation).to be_present
    expect(branch_confirmation).to be_present
  end

  it 'fully destroys branched backup metadata when a branched backup dataset is removed' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "destroy-#{SecureRandom.hex(4)}")
    create_doc_branching_fixture!(dataset: dataset, backup_dip: backup)

    pending 'branched backup dataset deletion can leave undeletable snapshot leftovers'

    described_class.fire(backup, recursive: true)

    expect(backup.reload.dataset_trees.count).to eq(0)
    expect(backup.reload.snapshot_in_pools.count).to eq(0)
    expect(SnapshotInPoolInBranch.joins(:snapshot_in_pool).where(snapshot_in_pools: { dataset_in_pool_id: backup.id }).count).to eq(0)
  end
end
