# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::SnapshotInPool::FreeClone do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  it 'queues clone deactivation using a confirmation' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "free-#{SecureRandom.hex(4)}")
    _, sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')
    clone = SnapshotInPoolClone.create!(
      snapshot_in_pool: sip,
      user_namespace_map: create_user_namespace_map!(user: user),
      name: "#{sip.snapshot_id}-existing.snapshot",
      state: :active
    )

    chain, = described_class.fire(clone)

    expect(tx_classes(chain)).to eq([Transactions::Storage::DeactivateSnapshotClone])

    confirmation = confirmations_for(chain).find { |row| row.class_name == 'SnapshotInPoolClone' }
    expect(confirmation.attr_changes).to eq(
      'state' => SnapshotInPoolClone.states.fetch('inactive')
    )
    expect(clone.reload.state).to eq('active')
    expect(SnapshotInPoolClone.where(id: clone.id)).to exist
  end
end
