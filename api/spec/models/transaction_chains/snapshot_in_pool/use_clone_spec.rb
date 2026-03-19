# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::SnapshotInPool::UseClone do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_snapshot_fixture
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "clone-#{SecureRandom.hex(4)}")
    _, sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')
    [pool, sip]
  end

  it 'creates a new clone, schedules CloneSnapshot, and increments the source reference count' do
    _, sip = create_snapshot_fixture
    userns_map = create_user_namespace_map!(user: user)

    chain, clone = described_class.fire(sip, userns_map)

    expect(clone).to be_persisted
    expect(clone.name).to eq("#{sip.snapshot_id}-#{clone.id}.snapshot")
    expect(tx_classes(chain)).to eq([Transactions::Storage::CloneSnapshot])

    increment = confirmations_for(chain).find { |row| row.confirm_type == 'increment_type' }
    expect(increment.row_pks).to eq('id' => sip.id)
    expect(increment.attr_changes).to eq('reference_count')
  end

  it 'activates an inactive clone' do
    _, sip = create_snapshot_fixture
    userns_map = create_user_namespace_map!(user: user)
    clone = SnapshotInPoolClone.create!(
      snapshot_in_pool: sip,
      user_namespace_map: userns_map,
      name: "#{sip.snapshot_id}-existing.snapshot",
      state: :inactive
    )

    chain, returned = described_class.fire(sip, userns_map)

    expect(returned.id).to eq(clone.id)
    expect(tx_classes(chain)).to eq([Transactions::Storage::ActivateSnapshotClone])

    confirmation = confirmations_for(chain).find { |row| row.class_name == 'SnapshotInPoolClone' }
    expect(confirmation.attr_changes).to eq('state' => SnapshotInPoolClone.states.fetch('active'))
  end

  it 'returns the active clone without emitting transactions' do
    _, sip = create_snapshot_fixture
    userns_map = create_user_namespace_map!(user: user)
    clone = SnapshotInPoolClone.create!(
      snapshot_in_pool: sip,
      user_namespace_map: userns_map,
      name: "#{sip.snapshot_id}-existing.snapshot",
      state: :active
    )

    chain, returned = use_chain_in_root!(described_class, args: [sip, userns_map])

    expect(returned.id).to eq(clone.id)
    expect(chain.transactions).to be_empty
  end
end
