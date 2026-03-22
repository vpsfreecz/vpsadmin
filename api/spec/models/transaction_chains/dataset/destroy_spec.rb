# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Destroy do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  it 'recursively destroys child datasets across primary and backup pools and skips already confirm_destroy pools' do
    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    stale_backup_pool = create_pool!(node: SpecSeed.node, role: :backup)

    parent, parent_primary = create_dataset_with_pool!(
      user: user,
      pool: primary_pool,
      name: "destroy-#{SecureRandom.hex(4)}"
    )
    parent_backup = attach_dataset_to_pool!(dataset: parent, pool: backup_pool)
    stale_backup = attach_dataset_to_pool!(
      dataset: parent,
      pool: stale_backup_pool,
      confirmed: :confirm_destroy
    )

    child, child_primary = create_dataset_with_pool!(
      user: user,
      pool: primary_pool,
      parent: parent,
      name: "child-#{SecureRandom.hex(4)}"
    )
    child_backup = attach_dataset_to_pool!(dataset: child, pool: backup_pool)

    parent_snap, = create_snapshot!(dataset: parent, dip: parent_primary, name: 'parent-snap')
    child_snap, = create_snapshot!(dataset: child, dip: child_primary, name: 'child-snap')

    parent_tree = create_tree!(dip: parent_backup, index: 0, head: true)
    parent_branch = create_branch!(tree: parent_tree, name: 'parent-head', head: true)
    attach_snapshot_to_branch!(
      sip: mirror_snapshot!(snapshot: parent_snap, dip: parent_backup),
      branch: parent_branch
    )

    child_tree = create_tree!(dip: child_backup, index: 0, head: true)
    child_branch = create_branch!(tree: child_tree, name: 'child-head', head: true)
    attach_snapshot_to_branch!(
      sip: mirror_snapshot!(snapshot: child_snap, dip: child_backup),
      branch: child_branch
    )

    chain, = described_class.fire(parent, nil, nil, nil)

    expect(tx_classes(chain)).to include(
      Transactions::Storage::DestroySnapshot,
      Transactions::Storage::DestroyBranch,
      Transactions::Storage::DestroyTree,
      Transactions::Storage::DestroyDataset
    )
    expect(parent_primary.reload.confirmed).to eq(:confirm_destroy)
    expect(parent_backup.reload.confirmed).to eq(:confirm_destroy)
    expect(child_primary.reload.confirmed).to eq(:confirm_destroy)
    expect(child_backup.reload.confirmed).to eq(:confirm_destroy)
    expect(parent_tree.reload.confirmed).to eq(:confirm_destroy)
    expect(parent_branch.reload.confirmed).to eq(:confirm_destroy)
    expect(child_tree.reload.confirmed).to eq(:confirm_destroy)
    expect(child_branch.reload.confirmed).to eq(:confirm_destroy)
    expect(stale_backup.reload.confirmed).to eq(:confirm_destroy)

    destroy_payloads = tx_payloads(chain)
                       .select { |payload| payload.has_key?('pool_fs') && payload.has_key?('name') }

    expect(destroy_payloads).to include(
      'pool_fs' => primary_pool.filesystem,
      'name' => parent.full_name
    )
    expect(destroy_payloads).to include(
      'pool_fs' => primary_pool.filesystem,
      'name' => child.full_name
    )
    expect(destroy_payloads).to include(
      'pool_fs' => backup_pool.filesystem,
      'name' => parent.full_name
    )
    expect(destroy_payloads).to include(
      'pool_fs' => backup_pool.filesystem,
      'name' => child.full_name
    )
    expect(destroy_payloads).not_to include(
      'pool_fs' => stale_backup_pool.filesystem,
      'name' => parent.full_name
    )
  end
end
