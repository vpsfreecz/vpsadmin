# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Snapshot do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'creates unconfirmed snapshot rows and appends create-snapshot' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "snap-#{SecureRandom.hex(4)}")

    chain, sip = described_class.fire(dip, label: 'spec-snapshot')

    expect(tx_classes(chain)).to eq([Transactions::Storage::CreateSnapshot])
    expect(sip.reload.confirmed).to eq(:confirm_create)
    expect(sip.snapshot.reload.confirmed).to eq(:confirm_create)
    expect(sip.snapshot.label).to eq('spec-snapshot')
    expect(sip.snapshot.name).to end_with('(unconfirmed)')
  end
end
