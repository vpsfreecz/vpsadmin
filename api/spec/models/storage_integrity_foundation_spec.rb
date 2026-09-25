# frozen_string_literal: true

require 'spec_helper'

RSpec.describe StorageFilesystemIdentity do
  let(:pool) { create_pool!(node: SpecSeed.node, role: :primary) }
  let(:backup_pool) { create_pool!(node: SpecSeed.node, role: :backup) }

  def scope_for(pool)
    StorageIntegrityScope.create!(pool:, scope_key: "pool:#{pool.id}")
  end

  it 'keeps one global freeze control after mode transitions' do
    control = StorageFreezeControl.singleton!
    expect(control.id).to eq(1)
    expect(control.mode).to be_in(%w[read_write read_only])
    expect(control.epoch).to be >= 0
    expect(StorageFreezeControl.count).to eq(1)

    expect do
      StorageFreezeControl.create!(id: 2)
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'binds a DIP scope to its actual pool' do
    _, dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "scope-#{SecureRandom.hex(3)}"
    )
    valid_scope = StorageIntegrityScope.new(
      pool:, dataset_in_pool: dip, scope_key: "dip:#{dip.id}"
    )
    expect(valid_scope).to be_valid

    wrong_pool = create_pool!(node: SpecSeed.node, role: :primary)
    valid_scope.pool = wrong_pool
    expect(valid_scope).not_to be_valid
    expect(valid_scope.errors[:pool]).to include('must match the catalog ID')

    valid_scope.pool_catalog_id = wrong_pool.id
    expect(valid_scope).not_to be_valid
    expect(valid_scope.errors[:pool]).to include('must own the dataset in pool')
  end

  it 'retains scope history after its live catalog pool is deleted' do
    scope = scope_for(pool)
    catalog_id = pool.id

    Pool.where(id: catalog_id).delete_all

    expect(scope.reload.pool_id).to be_nil
    expect(scope.pool_catalog_id).to eq(catalog_id)
    expect(scope.scope_key).to eq("pool:#{catalog_id}")
  end

  it 'requires exactly one catalog owner through the model' do
    identity = described_class.new(pool:)
    expect(identity).not_to be_valid
    expect(identity.errors[:base]).to include('exactly one catalog owner is required')

    _, dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "two-owners-#{SecureRandom.hex(3)}"
    )
    identity.owner_pool = pool
    identity.dataset_in_pool = dip
    expect(identity).not_to be_valid
    expect(identity.errors[:base]).to include('exactly one catalog owner is required')

    identity.dataset_in_pool = nil
    expect(identity).to be_valid
    identity.save!
  end

  it 'uses path and owner to distinguish duplicate ZFS GUIDs' do
    _, dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "identity-#{SecureRandom.hex(3)}"
    )
    root = described_class.create!(
      pool:, owner_pool: pool, zfs_path: pool.filesystem, zfs_guid: (2**64) - 1
    )
    child = described_class.create!(
      pool:, dataset_in_pool: dip, zfs_path: "#{pool.filesystem}/child",
      zfs_guid: (2**64) - 1
    )

    expect(child.path_digest).not_to eq(root.path_digest)
    expect(child.zfs_guid).to eq(root.zfs_guid)
    expect(
      described_class.new(
        pool:, dataset_in_pool: dip, zfs_path: pool.filesystem
      ).valid?
    ).to be(false)

    other_pool = create_pool!(node: pool.node, role: :primary)
    duplicate_on_node = described_class.new(
      pool: other_pool, owner_pool: other_pool, zfs_path: root.zfs_path
    )
    expect(duplicate_on_node).not_to be_valid
    expect(duplicate_on_node.errors[:zfs_path]).to include(
      'is already claimed on this node'
    )
  end

  it 'links a filesystem origin to one snapshot occurrence without changing SIP cardinality' do
    dataset, dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "origin-#{SecureRandom.hex(3)}"
    )
    _, sip = create_snapshot!(dataset:, dip:)
    identity = described_class.new(
      pool:, dataset_in_pool: dip, origin_state: :linked,
      origin_snapshot_in_pool: sip
    )
    expect(identity).to be_valid
    identity.origin_snapshot_in_pool_in_branch = SnapshotInPoolInBranch.new
    expect(identity).not_to be_valid
    expect(identity.errors[:base]).to include(
      'linked origin requires exactly one snapshot occurrence'
    )

    identity.origin_snapshot_in_pool_in_branch = nil
    identity.save!
    expect do
      SnapshotInPool.where(id: sip.id).delete_all
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'stores physical snapshot identity only on the occurrence for that pool role' do
    dataset, dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "snapshot-#{SecureRandom.hex(3)}"
    )
    snapshot, sip = create_snapshot!(dataset:, dip:)
    sip.zfs_guid = 42
    sip.zfs_owner_fs_guid = 41
    sip.zfs_path = "#{pool.filesystem}/disk@snapshot"
    sip.physical_presence = :present
    expect(sip).to be_valid

    backup_dip = attach_dataset_to_pool!(dataset:, pool: backup_pool)
    backup_sip = mirror_snapshot!(snapshot:, dip: backup_dip)
    backup_sip.zfs_guid = 42
    expect(backup_sip).not_to be_valid

    tree = create_tree!(dip: backup_dip)
    branch = create_branch!(tree:, name: 'main')
    entry = attach_snapshot_to_branch!(sip: backup_sip, branch:)
    entry.zfs_guid = 42
    entry.zfs_owner_fs_guid = 40
    entry.zfs_path = "#{backup_pool.filesystem}/tree.0/branch-main.0@snapshot"
    entry.physical_presence = :present
    expect(entry).to be_valid
  end

  it 'refuses aggregate backup SIP origins and mismatched backup branches' do
    dataset, primary_dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "backup-origin-#{SecureRandom.hex(3)}"
    )
    snapshot, = create_snapshot!(dataset:, dip: primary_dip)
    backup_dip = attach_dataset_to_pool!(dataset:, pool: backup_pool)
    backup_sip = mirror_snapshot!(snapshot:, dip: backup_dip)

    identity = described_class.new(
      pool: backup_pool, owner_pool: backup_pool, origin_state: :linked,
      origin_snapshot_in_pool: backup_sip
    )
    expect(identity).not_to be_valid
    expect(identity.errors[:base]).to include(
      'backup origin must identify a branch occurrence'
    )

    tree = create_tree!(dip: backup_dip)
    branch = create_branch!(tree:, name: 'main')
    entry = attach_snapshot_to_branch!(sip: backup_sip, branch:)
    identity.origin_snapshot_in_pool = nil
    identity.origin_snapshot_in_pool_in_branch = entry
    expect(identity).to be_valid

    _, other_dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool: backup_pool,
      name: "other-branch-#{SecureRandom.hex(3)}"
    )
    other_branch = create_branch!(tree: create_tree!(dip: other_dip), name: 'other')
    entry.update!(branch: other_branch)
    expect(identity).not_to be_valid
    expect(identity.errors[:base]).to include(
      'backup origin branch must match its snapshot placement'
    )
    entry.zfs_guid = 42
    expect(entry).not_to be_valid
    expect(entry.errors[:base]).to include(
      'physical identity is stored on the wrong snapshot occurrence'
    )
  end

  it 'retains failed attempts separately from reconciliation and bounds target sequence' do
    scope = scope_for(pool)
    intent = StorageMutationIntent.create!(
      token: SecureRandom.uuid, node: pool.node, kind: 'snapshot_create',
      manifest_digest: 'a' * 64, protocol_version: 1
    )
    attempt = StorageMutationAttempt.create!(
      storage_mutation_intent: intent, command_key: 'create',
      direction: :execute, attempt_number: 1, state: :failed
    )
    expect(attempt).to be_failed
    expect(intent.reload).to be_prepared

    intent_scope = StorageMutationIntentScope.create!(
      storage_mutation_intent: intent, storage_integrity_scope: scope,
      expected_epoch: 7
    )
    target = StorageMutationTarget.create!(
      storage_mutation_intent: intent, storage_mutation_intent_scope: intent_scope,
      command_key: 'create', sequence: 0, kind: 'snapshot',
      expected_path: "#{pool.filesystem}/dataset@snapshot"
    )
    duplicate = StorageMutationTarget.new(
      storage_mutation_intent: intent, storage_mutation_intent_scope: intent_scope,
      command_key: 'create', sequence: 0, kind: 'snapshot'
    )
    expect(duplicate).not_to be_valid
    duplicate.sequence = 1
    duplicate.storage_filesystem_identity = described_class.new
    duplicate.snapshot_in_pool = SnapshotInPool.new
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:base]).to include('at most one catalog link is allowed')

    other_scope = scope_for(create_pool!(node: SpecSeed.node, role: :backup))
    other_intent_scope = StorageMutationIntentScope.create!(
      storage_mutation_intent: intent, storage_integrity_scope: other_scope,
      expected_epoch: 12
    )
    expect(other_intent_scope.expected_epoch).to eq(12)
    expect(intent_scope.expected_epoch).to eq(7)

    first = StorageMutationTargetObservation.create!(
      storage_mutation_attempt: attempt, storage_mutation_target: target,
      before_presence: :missing, after_presence: :unknown
    )
    retry_attempt = StorageMutationAttempt.create!(
      storage_mutation_intent: intent, command_key: 'create',
      direction: :execute, attempt_number: 2, state: :succeeded
    )
    retry_observation = StorageMutationTargetObservation.create!(
      storage_mutation_attempt: retry_attempt, storage_mutation_target: target,
      before_presence: :missing, after_presence: :present, after_guid: 42
    )
    expect(first).to be_after_unknown
    expect(retry_observation).to be_after_present
    expect { retry_observation.update!(after_guid: 43) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect { retry_attempt.update!(after_digest: 'changed') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'requires complete observation evidence before recording a run' do
    scope = scope_for(pool)
    run = StorageObservationRun.create!(
      storage_integrity_scope: scope, collector_version: 1, mutation_epoch: 0
    )
    run.state = :complete
    expect(run).not_to be_valid
    expect(run.errors[:node_observed_from_at]).to include(
      'is required for a complete run'
    )
  end
end
