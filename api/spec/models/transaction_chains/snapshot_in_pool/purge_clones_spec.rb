# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::SnapshotInPool::PurgeClones do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_inactive_clone!
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "purge-#{SecureRandom.hex(4)}")
    _, sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')
    sip.update!(reference_count: 1)

    SnapshotInPoolClone.create!(
      snapshot_in_pool: sip,
      user_namespace_map: create_user_namespace_map!(user: user),
      name: "#{sip.snapshot_id}-inactive.snapshot",
      state: :inactive
    )
  end

  it 'removes inactive clones with keep_going rollback semantics and decrements the parent reference count' do
    clone = create_inactive_clone!

    chain, = described_class.fire

    expect(tx_classes(chain)).to eq([Transactions::Storage::RemoveClone])
    expect(chain.transactions.take!.reversible).to eq('keep_going')

    decrement = confirmations_for(chain).find { |row| row.confirm_type == 'decrement_type' }
    destroy = confirmations_for(chain).find { |row| row.class_name == 'SnapshotInPoolClone' }

    expect(decrement.row_pks).to eq('id' => clone.snapshot_in_pool.id)
    expect(decrement.attr_changes).to eq('reference_count')
    expect(destroy.confirm_type).to eq('destroy_type')
  end

  it 'skips locked inactive clones' do
    clone = create_inactive_clone!
    lock_holder = build_transaction_chain!(name: 'lock-holder')
    clone.acquire_lock(lock_holder)

    chain, = use_chain_in_root!(described_class)

    expect(chain.transactions).to be_empty
    expect(clone.reload.state).to eq('inactive')
  end

  it 'allows an empty chain when there are no inactive clones' do
    chain, = use_chain_in_root!(described_class)

    expect(chain.transactions).to be_empty
  end
end
