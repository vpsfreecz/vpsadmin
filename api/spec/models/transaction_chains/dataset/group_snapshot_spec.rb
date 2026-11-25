# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::GroupSnapshot do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  it 'executes a current shared plan action for every current member' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    dataset_a, dip_a = create_dataset_with_pool!(user: user, pool: pool, name: "scheduled-a-#{SecureRandom.hex(4)}")
    dataset_b, dip_b = create_dataset_with_pool!(user: user, pool: pool, name: "scheduled-b-#{SecureRandom.hex(4)}")
    [dataset_a, dataset_b].each { |dataset| attach_dataset_to_pool!(dataset: dataset, pool: backup_pool) }
    _, environment_plan = create_daily_backup_env_plan!(environment: pool.node.location.environment)
    [dip_a, dip_b].each { |dip| dip.add_plan(environment_plan) }
    action = dip_a.group_snapshots.first!.dataset_action

    expect(dip_b.group_snapshots.first!.dataset_action_id).to eq(action.id)
    chain, prepared = action.execute

    expect(chain).to be_a(described_class)
    expect(chain).to be_queued
    expect(tx_classes(chain)).to eq([Transactions::Storage::CreateSnapshots])
    expect(prepared.map(&:dataset_in_pool_id)).to contain_exactly(dip_a.id, dip_b.id)
    snapshots = Snapshot.where(dataset_id: [dataset_a.id, dataset_b.id]).to_a
    copies = SnapshotInPool.where(dataset_in_pool_id: [dip_a.id, dip_b.id]).to_a
    expect(snapshots.size).to eq(2)
    expect(copies.size).to eq(2)
    expect(snapshots.map(&:confirmed)).to all(eq(:confirm_create))
    expect(copies.map(&:confirmed)).to all(eq(:confirm_create))
  end

  it 'creates one grouped snapshot transaction for all unlocked datasets' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset_a, dip_a = create_dataset_with_pool!(user: user, pool: pool, name: "group-a-#{SecureRandom.hex(4)}")
    dataset_b, dip_b = create_dataset_with_pool!(user: user, pool: pool, name: "group-b-#{SecureRandom.hex(4)}")

    chain, = described_class.fire([dip_a, dip_b])
    snapshots = Snapshot.where(dataset_id: [dataset_a.id, dataset_b.id]).order(:id).to_a
    sips = SnapshotInPool.where(dataset_in_pool_id: [dip_a.id, dip_b.id]).order(:id).to_a

    expect(tx_classes(chain)).to eq([Transactions::Storage::CreateSnapshots])
    expect(snapshots.size).to eq(2)
    expect(sips.size).to eq(2)
    expect(snapshots.map(&:confirmed)).to all(eq(:confirm_create))
    expect(sips.map(&:confirmed)).to all(eq(:confirm_create))
  end

  it 'skips locked datasets instead of failing the whole group' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset_a, dip_a = create_dataset_with_pool!(user: user, pool: pool, name: "group-a-#{SecureRandom.hex(4)}")
    dataset_b, dip_b = create_dataset_with_pool!(user: user, pool: pool, name: "group-b-#{SecureRandom.hex(4)}")
    lock_holder = build_transaction_chain!(name: 'lock-holder')

    lock_holder.lock(dip_b)

    chain, = described_class.fire([dip_a, dip_b])

    expect(tx_classes(chain)).to eq([Transactions::Storage::CreateSnapshots])
    expect(Snapshot.where(dataset_id: dataset_a.id).count).to eq(1)
    expect(Snapshot.where(dataset_id: dataset_b.id).count).to eq(0)
    expect(SnapshotInPool.where(dataset_in_pool_id: dip_a.id).count).to eq(1)
    expect(SnapshotInPool.where(dataset_in_pool_id: dip_b.id).count).to eq(0)
  end

  it 'raises on locked datasets in strict mode' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    _dataset_a, dip_a = create_dataset_with_pool!(user: user, pool: pool, name: "group-a-#{SecureRandom.hex(4)}")
    _dataset_b, dip_b = create_dataset_with_pool!(user: user, pool: pool, name: "group-b-#{SecureRandom.hex(4)}")
    lock_holder = build_transaction_chain!(name: 'lock-holder')

    lock_holder.lock(dip_b)

    expect do
      described_class.fire([dip_a, dip_b], strict: true)
    end.to raise_error(ResourceLocked)
  end

  it 'uses supplied snapshot label and lets nodectld confirm the final name' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset_a, dip_a = create_dataset_with_pool!(user: user, pool: pool, name: "group-a-#{SecureRandom.hex(4)}")
    dataset_b, dip_b = create_dataset_with_pool!(user: user, pool: pool, name: "group-b-#{SecureRandom.hex(4)}")

    chain, = described_class.fire(
      [dip_a, dip_b],
      label: 'Created for VPS replace 1 -> 2',
      strict: true
    )

    payload = tx_payloads(chain).first
    snapshots = Snapshot.where(dataset_id: [dataset_a.id, dataset_b.id]).order(:id).to_a

    expect(snapshots.map(&:name)).to all(match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} \(unconfirmed\)\z/))
    expect(snapshots.map(&:label)).to eq([
                                           'Created for VPS replace 1 -> 2',
                                           'Created for VPS replace 1 -> 2'
                                         ])
    expect(payload.keys).to eq(['snapshots'])
    expect(payload.fetch('snapshots').map { |row| row.fetch('snapshot_id') }).to match_array(snapshots.map(&:id))
  end

  it 'uses one generated timestamp prefix for all created snapshots' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset_a, dip_a = create_dataset_with_pool!(user: user, pool: pool, name: "group-a-#{SecureRandom.hex(4)}")
    dataset_b, dip_b = create_dataset_with_pool!(user: user, pool: pool, name: "group-b-#{SecureRandom.hex(4)}")

    described_class.fire([dip_a, dip_b])

    names = Snapshot.where(dataset_id: [dataset_a.id, dataset_b.id]).pluck(:name)
    prefixes = names.map { |name| name.delete_suffix(' (unconfirmed)') }.uniq

    expect(names).to all(end_with(' (unconfirmed)'))
    expect(prefixes.size).to eq(1)
  end
end
