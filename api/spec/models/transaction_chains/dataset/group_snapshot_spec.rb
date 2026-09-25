# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::GroupSnapshot do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

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
    intent = StorageMutationIntent.find_by!(transaction_id: chain.transactions.sole.id)
    expect(intent.storage_mutation_targets.pluck(:kind).uniq).to eq(['observer_unbounded'])
  end

  it 'stages one ordered signed group only under explicit test injection' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dips = 2.times.map do |index|
      _, dip = create_dataset_with_pool!(
        user:, pool:, name: "strict-group-#{index}-#{SecureRandom.hex(3)}"
      )
      StorageFilesystemIdentity.create!(
        pool:, dataset_in_pool: dip,
        zfs_path: "#{pool.filesystem}/#{dip.dataset.full_name}",
        zfs_guid: 3000 + index, physical_presence: :present
      )
      dip
    end
    allow(Transactions::Storage::CreateSnapshots)
      .to receive(:test_only_strict_group_snapshot?).and_return(true)
    unlock_transaction_signer!

    chain, sips = described_class.fire(dips, strict: true)
    transaction = chain.transactions.sole
    payload = JSON.parse(transaction.input).fetch('input')
    intent = StorageMutationIntent.find_by!(transaction_id: transaction.id)
    targets = intent.storage_mutation_targets.order(:sequence).to_a

    expect(transaction.signature).not_to be_nil
    expect(payload.fetch('storage_guard')).to include(
      'token' => intent.token, 'manifest_digest' => intent.manifest_digest,
      'registry_version' => StorageEffectRegistry::VERSION
    )
    expect(payload.fetch('planned_snapshot_name')).to eq(
      sips.first.snapshot.name.delete_suffix(' (unconfirmed)')
    )
    expect(payload.fetch('snapshots').map { |row| row.fetch('snapshot_id') })
      .to eq(sips.sort_by(&:id).map(&:snapshot_id))
    expect(targets.map(&:sequence)).to eq([0, 1, 2])
    expect(targets.map(&:kind)).to eq(%w[observer_unbounded snapshot_create snapshot_create])
    expect(targets.map { |target| target.storage_mutation_intent_scope.storage_integrity_scope.scope_key })
      .to eq(["pool:#{pool.id}", *sips.sort_by(&:id).map { |sip| "dip:#{sip.dataset_in_pool_id}" }])
    expect(targets.drop(1).map(&:snapshot_in_pool_id)).to eq(sips.sort_by(&:id).map(&:id))
    expect(targets.drop(1).map(&:expected_owner_fs_guid)).to eq([3000, 3001])
    expect(targets.drop(1).map(&:expected_path)).to eq(
      sips.sort_by(&:id).map do |sip|
        "#{pool.filesystem}/#{sip.dataset_in_pool.dataset.full_name}@#{payload.fetch('planned_snapshot_name')}"
      end
    )
  ensure
    lock_transaction_signer!
  end

  it 'does not stage an unsigned test-only strict group' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    _, dip = create_dataset_with_pool!(
      user:, pool:, name: "unsigned-strict-group-#{SecureRandom.hex(3)}"
    )
    StorageFilesystemIdentity.create!(
      pool:, dataset_in_pool: dip,
      zfs_path: "#{pool.filesystem}/#{dip.dataset.full_name}",
      zfs_guid: 3000, physical_presence: :present
    )
    allow(Transactions::Storage::CreateSnapshots)
      .to receive(:test_only_strict_group_snapshot?).and_return(true)
    allow(VpsAdmin::API::TransactionSigner).to receive(:sign_base64).and_return(nil)
    before = [Snapshot.count, StorageMutationIntent.count]

    expect do
      described_class.fire([dip], strict: true)
    end.to raise_error(VpsAdmin::API::Exceptions::StorageSignerUnavailable)
    expect([Snapshot.count, StorageMutationIntent.count]).to eq(before)
  end

  it 'rejects mixed Pools before staging test-only strict authority' do
    pools = 2.times.map { create_pool!(node: SpecSeed.node, role: :primary) }
    dips = pools.map.with_index do |pool, index|
      _, dip = create_dataset_with_pool!(
        user:, pool:, name: "mixed-group-#{index}-#{SecureRandom.hex(3)}"
      )
      dip
    end
    allow(Transactions::Storage::CreateSnapshots)
      .to receive(:test_only_strict_group_snapshot?).and_return(true)
    before = [StorageMutationIntent.count, StorageMutationTarget.count]

    expect do
      described_class.fire(dips, strict: true)
    end.to raise_error(/no bounded exact manifest/)
    expect([StorageMutationIntent.count, StorageMutationTarget.count]).to eq(before)
  end

  it 'rejects an oversized test-only group without retaining staged rows' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dips = 33.times.map do |index|
      _, dip = create_dataset_with_pool!(
        user:, pool:, name: "large-group-#{index}-#{SecureRandom.hex(3)}"
      )
      dip
    end
    allow(Transactions::Storage::CreateSnapshots)
      .to receive(:test_only_strict_group_snapshot?).and_return(true)
    before = [Snapshot.count, SnapshotInPool.count, StorageMutationIntent.count]

    expect do
      described_class.fire(dips, strict: true)
    end.to raise_error(/no bounded exact manifest/)
    expect([Snapshot.count, SnapshotInPool.count, StorageMutationIntent.count]).to eq(before)
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
