# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DatasetInPool::DetachBackupHeads do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def ensure_available_node!
    NodeCurrentStatus.find_or_create_by!(node: SpecSeed.node) do |status|
      status.vpsadmin_version = 'spec'
      status.kernel = 'spec'
      status.update_count = 1
      status.pool_checked_at = Time.now.utc
    end
  end

  it 'clears head flags on all backup trees and their head branches and records an affect concern' do
    ensure_available_node!

    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool_a = create_pool!(node: SpecSeed.other_node, role: :backup)
    backup_pool_b = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, primary = create_dataset_with_pool!(user: user, pool: primary_pool, name: "detach-#{SecureRandom.hex(4)}")
    backup_a = attach_dataset_to_pool!(dataset: dataset, pool: backup_pool_a)
    backup_b = attach_dataset_to_pool!(dataset: dataset, pool: backup_pool_b)

    tree_a0 = create_tree!(dip: backup_a, index: 0, head: true)
    branch_a0 = create_branch!(tree: tree_a0, name: 'head-a0', head: true)
    tree_a1 = create_tree!(dip: backup_a, index: 1, head: false)
    branch_a1 = create_branch!(tree: tree_a1, name: 'head-a1', head: true)
    tree_b0 = create_tree!(dip: backup_b, index: 0, head: true)
    branch_b0 = create_branch!(tree: tree_b0, name: 'head-b0', head: true)

    chain, = described_class.fire(primary)

    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Dataset', dataset.id])

    confirmations = confirmations_for(chain).map do |row|
      [row.class_name, row.row_pks, row.attr_changes]
    end

    expect(confirmations).to include(
      ['DatasetTree', { 'id' => tree_a0.id }, { 'head' => 0 }],
      ['DatasetTree', { 'id' => tree_a1.id }, { 'head' => 0 }],
      ['DatasetTree', { 'id' => tree_b0.id }, { 'head' => 0 }],
      ['Branch', { 'id' => branch_a0.id }, { 'head' => 0 }],
      ['Branch', { 'id' => branch_a1.id }, { 'head' => 0 }],
      ['Branch', { 'id' => branch_b0.id }, { 'head' => 0 }]
    )
  end

  it 'allows an empty chain when there are no backup heads to detach' do
    ensure_available_node!

    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    _, primary = create_dataset_with_pool!(user: user, pool: primary_pool, name: "detach-#{SecureRandom.hex(4)}")

    chain, = use_chain_in_root!(described_class, args: [primary])

    expect(chain.transactions).to be_empty
  end
end
