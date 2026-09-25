# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Snapshot do
  around do |example|
    unlock_transaction_signer!
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

  it 'rolls back staging when the next minute of names is occupied' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user:, pool:, name: "snap-full-#{SecureRandom.hex(4)}")
    fixed_time = Time.utc(2026, 9, 25, 23, 46, 59)

    60.times do |offset|
      Snapshot.create!(
        dataset:, history_id: dataset.current_history_id,
        name: (fixed_time + offset).strftime('%Y-%m-%dT%H:%M:%S'),
        confirmed: Snapshot.confirmed(:confirmed)
      )
    end
    before = [Snapshot.count, TransactionChain.count, StorageMutationIntent.count]
    allow(Time).to receive(:now).and_return(fixed_time)

    expect do
      described_class.fire(dip)
    end.to raise_error(RuntimeError, 'unable to allocate snapshot name within 60 seconds')
    expect([Snapshot.count, TransactionChain.count, StorageMutationIntent.count]).to eq(before)
  end

  it 'allocates names across separate pool copies of one dataset' do
    node = SpecSeed.node
    primary_pool = create_pool!(node:, role: :primary)
    backup_pool = create_pool!(node:, role: :backup)
    dataset, primary_dip = create_dataset_with_pool!(
      user:, pool: primary_pool, name: "snap-copies-#{SecureRandom.hex(4)}"
    )
    backup_dip = attach_dataset_to_pool!(dataset:, pool: backup_pool)
    fixed_time = Time.utc(2026, 9, 25, 23, 46, 59)
    allow(Time).to receive(:now).and_return(fixed_time)

    _, primary_sip = described_class.fire(primary_dip)
    _, backup_sip = described_class.fire(backup_dip)

    expect([primary_sip, backup_sip].map { |sip| sip.snapshot.name }).to eq(
      [fixed_time, fixed_time + 1].map do |time|
        "#{time.strftime('%Y-%m-%dT%H:%M:%S')} (unconfirmed)"
      end
    )
  end
end
