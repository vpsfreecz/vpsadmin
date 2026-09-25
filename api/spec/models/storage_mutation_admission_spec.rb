# frozen_string_literal: true

require 'spec_helper'

RSpec.describe StorageMutationAdmission do
  around do |example|
    with_current_context(user: SpecSeed.user) do |session|
      unlock_transaction_signer!
      begin
        example.run
      ensure
        session.destroy! if example.metadata[:no_transaction]
      end
    end
  ensure
    lock_transaction_signer!
  end

  def snapshot_dataset
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    _, dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "guard-#{SecureRandom.hex(4)}"
    )
    [pool, dip]
  end

  def observer_pools(count:)
    node = SpecSeed.node
    existing = Pool.where(node_id: node.id).count
    (count - existing).times { create_pool!(node:, role: :primary) }
    Pool.where(node_id: node.id).order(:id).to_a
  end

  def observer_vps(pool)
    _, dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "observer-#{SecureRandom.hex(4)}"
    )
    create_vps_for_dataset!(user: SpecSeed.user, node: pool.node, dataset_in_pool: dip)
  end

  def observer_chain
    TransactionChain.create!(
      name: 'observer_spec', type: 'TransactionChain', state: :queued,
      size: 0, progress: 0, user: User.current,
      user_session: UserSession.current, urgent_rollback: false
    )
  end

  def stage_direct(klass, *args)
    TransactionChain.transaction(requires_new: true) do
      klass.fire_chained(observer_chain, nil, args:, urgent: false, prio: 0)
    end
  end

  def freeze_as_admin!(read_only: true, reason: 'spec freeze')
    control = StorageFreezeControl.singleton!
    control.update!(mode: read_only ? :read_only : :read_write,
                    epoch: control.epoch + 1, reason:)
  end

  it 'rejects a read-only admission before staging snapshot rows' do
    _, dip = snapshot_dataset
    freeze_as_admin!
    before = Snapshot.count
    before_intents = StorageMutationIntent.count

    expect do
      TransactionChains::Dataset::Snapshot.fire(dip)
    end.to raise_error(VpsAdmin::API::Exceptions::StorageReadOnly)
    expect(Snapshot.count).to eq(before)
    expect(StorageMutationIntent.count).to eq(before_intents)
  end

  it 'records the ordered Pool observer and DIP snapshot targets for 5204' do
    pool, dip = snapshot_dataset
    other_pool = create_pool!(node: pool.node, role: :primary)
    chain, sip = TransactionChains::Dataset::Snapshot.fire(dip)
    transaction = chain.transactions.sole
    intent = StorageMutationIntent.find_by!(transaction_id: transaction.id)
    payload = JSON.parse(transaction.input).fetch('input')

    expect(payload.fetch('storage_guard')).to include(
      'token' => intent.token, 'manifest_digest' => intent.manifest_digest,
      'registry_version' => StorageEffectRegistry::VERSION,
      'protocol_version' => StorageMutationJournal::PROTOCOL_VERSION
    )
    links = intent.storage_mutation_intent_scopes.includes(:storage_integrity_scope).to_a
    expect(links.length).to eq(2)
    expect(links.map { |link| link.storage_integrity_scope.scope_key })
      .to contain_exactly("pool:#{pool.id}", "dip:#{dip.id}")
    targets = intent.storage_mutation_targets.order(:sequence).to_a
    expect(targets.length).to eq(2)
    pool_target, snapshot_target = targets
    expect([pool_target.sequence, snapshot_target.sequence]).to eq([0, 1])
    expect(pool_target).to have_attributes(
      command_key: '5204', kind: 'observer_unbounded',
      snapshot_in_pool_id: nil, snapshot_in_pool_in_branch_id: nil,
      storage_filesystem_identity_id: nil, catalog_kind: nil, catalog_id: nil,
      expected_path: nil, expected_guid: nil, expected_owner_fs_guid: nil
    )
    expect(pool_target.storage_mutation_intent_scope.storage_integrity_scope.scope_key)
      .to eq("pool:#{pool.id}")
    expect(snapshot_target).to have_attributes(
      command_key: '5204', kind: 'snapshot_create', snapshot_in_pool_id: sip.id,
      snapshot_in_pool_in_branch_id: nil, storage_filesystem_identity_id: nil,
      catalog_kind: 'SnapshotInPool', catalog_id: sip.id, expected_guid: nil
    )
    expect(snapshot_target.expected_owner_fs_guid)
      .to eq(StorageFilesystemIdentity.find_by(dataset_in_pool_id: dip.id)&.zfs_guid)
    expect(snapshot_target.storage_mutation_intent_scope.storage_integrity_scope.scope_key)
      .to eq("dip:#{dip.id}")
    expect(snapshot_target.expected_path).to eq("#{pool.filesystem}/#{dip.dataset.full_name}@" \
                                                "#{payload.fetch('planned_snapshot_name')}")
    expect(StorageIntegrityScope.find_by(scope_key: "pool:#{other_pool.id}")).to be_nil
  end

  it 'stages an unsigned snapshot observer with exact targets' do
    _, dip = snapshot_dataset
    allow(VpsAdmin::API::TransactionSigner).to receive(:sign_base64).and_return(nil)
    chain, = TransactionChains::Dataset::Snapshot.fire(dip)
    transaction = chain.transactions.sole
    intent = StorageMutationIntent.find_by!(transaction_id: transaction.id)
    targets = intent.storage_mutation_targets.order(:sequence).to_a

    expect(transaction.signature).to be_nil
    expect(JSON.parse(transaction.input).fetch('input').fetch('storage_guard'))
      .to include('token' => intent.token, 'manifest_digest' => intent.manifest_digest)
    expect(targets.map(&:kind)).to eq(%w[observer_unbounded snapshot_create])
    expect(targets.last.snapshot_in_pool.dataset_in_pool_id).to eq(dip.id)
  end

  it 'keeps a backup SIP on the opaque observer path' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    _, dip = create_dataset_with_pool!(
      user: SpecSeed.user, pool:, name: "backup-guard-#{SecureRandom.hex(4)}"
    )
    chain, = TransactionChains::Dataset::Snapshot.fire(dip)
    transaction = chain.transactions.sole
    intent = StorageMutationIntent.find_by!(transaction_id: transaction.id)

    expect(JSON.parse(transaction.input).fetch('input')).not_to have_key('storage_guard')
    expect(intent.storage_mutation_targets.where(kind: 'snapshot_create')).to be_empty
    expect(intent.storage_mutation_targets.pluck(:kind)).to include('observer_unbounded')
  end

  it 'refuses the API-only 5225 handle before params or staging in both modes' do
    klass = Transactions::Storage::EnsureUgidOffset
    chain = observer_chain
    allow(klass).to receive(:new).and_call_original
    before = [Transaction.count, StorageMutationIntent.count,
              StorageMutationTarget.count, StorageMutationIntentScope.count,
              StorageIntegrityScope.count]

    [0, 1].each do |mode|
      StorageFreezeControl.singleton!.update_columns(mode:)
      expect do
        klass.fire_chained(chain, nil, args: [SpecSeed.pool], urgent: false)
      end.to raise_error(VpsAdmin::API::Exceptions::OperationNotSupported,
                         'This storage operation is not supported.')
    end

    expect(klass).not_to have_received(:new)
    expect([Transaction.count, StorageMutationIntent.count,
            StorageMutationTarget.count, StorageMutationIntentScope.count,
            StorageIntegrityScope.count]).to eq(before)
  end

  it 'gates a VPS queue transaction before its params callback' do
    freeze_as_admin!(reason: 'vps queue spec')

    expect(Transactions::Vps::Destroy.queue).to eq(:vps)
    expect(Transactions::Vps::Destroy.storage_effect).to eq(:osctl_topology)
    expect do
      TransactionChain.transaction do
        Transactions::Vps::Destroy.fire_chained(nil, nil, { args: [] })
      end
    end.to raise_error(VpsAdmin::API::Exceptions::StorageReadOnly)
  end

  it 'classifies osctl storage effects in execute and rollback handles' do
    handles = %w[
      1001 1002 1003 2020 2029 3001 3002 3003 3030 3031 3032 3033
      3034 3035 3040 3041 8001
    ].map(&:to_i)

    effects = handles.map { |handle| Transaction.for_type(handle).storage_effect }
    expect(effects).to all(be_present)
    expect(Transactions::Vps::SendConfig.storage_effect).to eq(:osctl_send)
    expect(Transactions::Vps::SendRollbackConfig.storage_effect)
      .to eq(:osctl_send_rollback)
  end

  it 'refuses runtime dataset routes before their params or staging callbacks' do
    freeze_as_admin!(reason: 'runtime route spec')
    classes = [Transactions::Vps::Start, Transactions::Vps::Stop,
               Transactions::Vps::Restart, Transactions::Vps::Passwd,
               Transactions::Vps::Resources, Transactions::Storage::DownloadSnapshot,
               Transactions::Storage::RemoveDownload,
               Transactions::NetworkInterface::Rename] +
              (5401..5407).map { |handle| Transaction.for_type(handle) }
    before = [Transaction.count, StorageMutationIntent.count, StorageIntegrityScope.count]

    classes.each do |klass|
      expect do
        TransactionChain.transaction(requires_new: true) do
          klass.fire_chained(nil, nil, args: [])
        end
      end.to raise_error(VpsAdmin::API::Exceptions::StorageReadOnly)
    end
    expect([Transaction.count, StorageMutationIntent.count, StorageIntegrityScope.count])
      .to eq(before)
  end

  it 'admits no-impact data writers without changing verified topology scopes' do
    pool = SpecSeed.pool
    vps = observer_vps(pool)
    resources_vps = observer_vps(pool)
    scope = StorageIntegrityScope.create!(
      pool:, scope_key: "pool:#{pool.id}", state: :verified, mutation_epoch: 9
    )
    snapshot = Struct.new(:dataset, :name).new(vps.dataset_in_pool.dataset, 'spec-snapshot')
    download = Struct.new(
      :pool, :snapshot, :secret_key, :file_name, :format, :id, :from_snapshot
    ).new(pool, snapshot, 'spec-key', 'spec-file', :archive, 123, nil)
    before = StorageMutationIntent.count

    TransactionChains::Vps::Passwd.fire(vps, 'spec-password')
    TransactionChains::Vps::SetResources.fire(resources_vps, [])
    stage_direct(Transactions::Storage::DownloadSnapshot, download)
    stage_direct(Transactions::Storage::RemoveDownload, download)

    expect(StorageMutationIntent.count).to eq(before)
    expect(scope.reload).to be_verified
    expect(scope.mutation_epoch).to eq(9)
  end

  it 'uses only the catalog owner Pool for dependency effects' do
    pool, dip = snapshot_dataset
    other_pool = create_pool!(node: pool.node, role: :primary)
    pool_scope = StorageIntegrityScope.create!(
      pool:, scope_key: "pool:#{pool.id}", state: :verified, mutation_epoch: 2
    )
    other_scope = StorageIntegrityScope.create!(
      pool: other_pool, scope_key: "pool:#{other_pool.id}",
      state: :verified, mutation_epoch: 2
    )

    property = stage_direct(Transactions::Storage::SetDataset, dip, {})
    export = Struct.new(
      :id, :dataset_in_pool, :snapshot_in_pool_clone, :path, :fsid
    ).new(nil, dip, nil, '/spec-export', 'spec-fsid')
    hosts = stage_direct(Transactions::Export::AddHosts, export, [])

    [property, hosts].each do |transaction|
      intent = StorageMutationIntent.find_by!(transaction_id: transaction.id)
      expect(intent.kind).to start_with('dependency_')
      expect(intent.storage_mutation_targets.pluck(:kind)).to eq(['observer_dependency'])
      expect(intent.storage_mutation_intent_scopes.sole.storage_integrity_scope.pool_id)
        .to eq(pool.id)
    end
    expect(pool_scope.reload.mutation_epoch).to eq(4)
    expect(other_scope.reload).to be_verified
    expect(other_scope.mutation_epoch).to eq(2)
  end

  it 'keeps a distinct catalog identity journal and falls back when its owner is unknown' do
    pool = SpecSeed.pool
    other_pool = create_pool!(node: pool.node, role: :primary)

    transaction = stage_direct(Transactions::Storage::CloneSnapshotName, pool.node, {})
    intent = StorageMutationIntent.find_by!(transaction_id: transaction.id)

    expect(intent.kind).to start_with('catalog_identity_')
    expect(intent.storage_mutation_targets.pluck(:kind).uniq)
      .to eq(['observer_catalog_identity'])
    scope_pool_ids = intent.storage_mutation_intent_scopes.joins(:storage_integrity_scope)
                           .pluck('storage_integrity_scopes.pool_id')
    expect(scope_pool_ids).to include(pool.id, other_pool.id)
    expect(scope_pool_ids).to match_array(Pool.where(node_id: pool.node_id).pluck(:id))
  end

  it 'falls back to all node Pools when a dependency path has duplicate claims' do
    pool, dip = snapshot_dataset
    create_pool!(node: pool.node, role: :primary, filesystem: pool.filesystem)

    transaction = stage_direct(Transactions::Storage::SetDataset, dip, {})
    intent = StorageMutationIntent.find_by!(transaction_id: transaction.id)

    expect(intent.storage_mutation_intent_scopes.count)
      .to eq(Pool.where(node_id: pool.node_id).count)
  end

  it 'advances every Pool scope in one ordered observer manifest across batches' do
    pools = observer_pools(count: 65)
    pools.each do |pool|
      StorageIntegrityScope.create!(
        pool:, scope_key: "pool:#{pool.id}", state: :verified, mutation_epoch: 3
      )
    end
    vps = observer_vps(pools.first)

    chain, = TransactionChains::Vps::Start.fire(vps)
    intent = StorageMutationIntent.find_by!(transaction_id: chain.transactions.sole.id)
    links = intent.storage_mutation_intent_scopes.order(:id).to_a
    targets = intent.storage_mutation_targets.order(:sequence).to_a

    expect(links.length).to eq(65)
    expect(targets.length).to eq(65)
    expect(targets.map(&:sequence)).to eq((0...65).to_a)
    expect(targets.map { |target| target.storage_mutation_intent_scope.storage_integrity_scope.pool_id })
      .to eq(pools.map(&:id))
    scopes = StorageIntegrityScope.where(pool_id: pools.map(&:id)).to_a
    expect(scopes.length).to eq(65)
    expect(scopes).to all(be_unverified)
    expect(scopes.map(&:mutation_epoch)).to all(eq(4))
  end

  it 'rolls back all scope epochs and staged rows on a later observer batch failure' do
    pools = observer_pools(count: 65)
    pools.each do |pool|
      StorageIntegrityScope.create!(
        pool:, scope_key: "pool:#{pool.id}", state: :verified, mutation_epoch: 3
      )
    end
    vps = observer_vps(pools.first)
    before = [TransactionChain.count, Transaction.count, StorageMutationIntent.count,
              StorageMutationIntentScope.count, StorageMutationTarget.count]
    advanced = 0
    allow(StorageMutationJournal).to receive(:advance_scope!).and_wrap_original do |original, *args|
      advanced += 1
      raise 'injected second-batch failure' if advanced == 65

      original.call(*args)
    end

    expect do
      TransactionChains::Vps::Start.fire(vps)
    end.to raise_error('injected second-batch failure')
    expect(advanced).to eq(65)
    expect([TransactionChain.count, Transaction.count, StorageMutationIntent.count,
            StorageMutationIntentScope.count, StorageMutationTarget.count]).to eq(before)
    scopes = StorageIntegrityScope.where(pool_id: pools.map(&:id)).to_a
    expect(scopes.length).to eq(65)
    expect(scopes).to all(be_verified)
    expect(scopes.map(&:mutation_epoch)).to all(eq(3))
  end

  it 'invalidates a verified Pool scope for an admitted VPS runtime effect' do
    pool = SpecSeed.pool
    scope = StorageIntegrityScope.create!(
      pool:, scope_key: "pool:#{pool.id}", state: :verified, mutation_epoch: 7
    )
    vps = observer_vps(pool)

    chain, = TransactionChains::Vps::Start.fire(vps)
    intent = StorageMutationIntent.find_by!(transaction_id: chain.transactions.sole.id)

    expect(scope.reload).to be_unverified
    expect(scope.mutation_epoch).to eq(8)
    expect(intent.kind).to eq('osctl_runtime_topology')
    expect(intent.storage_mutation_targets.pluck(:kind)).to include('observer_unbounded')
  end

  it 'retains needs_reconcile while advancing a catalog-only scope epoch' do
    pool, dip = snapshot_dataset
    scope = StorageIntegrityScope.create!(
      pool:, dataset_in_pool: dip, scope_key: "dip:#{dip.id}",
      state: :needs_reconcile, mutation_epoch: 4
    )

    StorageMutationJournal.mark_catalog_topology!([dip])

    expect(scope.reload).to be_needs_reconcile
    expect(scope.mutation_epoch).to eq(5)
  end
end
