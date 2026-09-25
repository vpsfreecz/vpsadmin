# frozen_string_literal: true

require 'spec_helper'

RSpec.describe StorageObserverSettlement do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def chain(state: :queued, size: 1)
    TransactionChain.create!(
      name: 'observer_spec', type: 'TransactionChain', state:, size:, progress: 0,
      user: SpecSeed.user, urgent_rollback: false
    )
  end

  def transaction(chain, handle: 5216)
    Transaction.create!(
      transaction_chain: chain, node: SpecSeed.node, user: SpecSeed.user,
      handle:, queue: 'storage', urgent: false, priority: 0, status: 0,
      input: '{}', reversible: :is_reversible
    )
  end

  def intent(chain, transaction)
    StorageMutationIntent.create!(
      storage_transaction: transaction, transaction_chain: chain,
      node: SpecSeed.node, token: SecureRandom.hex(24), kind: 'observer_dependency',
      protocol_version: 1, manifest_digest: 'a' * 64
    )
  end

  def opaque_backup_snapshot(chain, transaction, pool:)
    transaction.update_columns(input: {
      transaction_chain: chain.id, handle: 5204, node: pool.node_id,
      input: { pool_fs: pool.filesystem }
    }.to_json)
    record = intent(chain, transaction)
    record.update_columns(kind: 'snapshot_create')
    target = observer_pool_target(record, pool, sequence: 0)
    [record, target]
  end

  def observer_pool_target(record, pool, sequence:)
    scope = StorageIntegrityScope.create!(
      pool:, scope_key: "pool:#{pool.id}", state: :unverified, mutation_epoch: 1
    )
    linked = StorageMutationIntentScope.create!(
      storage_mutation_intent: record, storage_integrity_scope: scope,
      expected_epoch: scope.mutation_epoch
    )
    StorageMutationTarget.create!(
      storage_mutation_intent: record, storage_mutation_intent_scope: linked,
      command_key: '5204', sequence:, kind: 'observer_unbounded'
    )
  end

  def finish(transaction, direction: 'execute', status: 'ok', skipped: false)
    output = { direction => { 'status' => status } }
    output.fetch(direction)['skipped'] = true if skipped
    transaction.update_columns(
      done: direction == 'rollback' ? 2 : 1,
      status: { 'failed' => 0, 'ok' => 1, 'warning' => 2 }.fetch(status),
      output: output.to_json, finished_at: Time.current
    )
  end

  before do
    StorageFreezeControl.singleton!.update_columns(mode: 1)
  end

  it 'catches up a complete old-node chain once without verifying any scope' do
    completed = chain(state: :done, size: 2)
    first = transaction(completed)
    second = transaction(completed, handle: 5405)
    first_intent = intent(completed, first)
    second_intent = intent(completed, second)
    finish(first)
    finish(second)

    result = described_class.catch_up!
    expect(result[:settled_intents]).to eq(2)
    expect(result[:settled_chain_ids]).to eq([completed.id])
    expect([first_intent.reload, second_intent.reload]).to all(
      have_attributes(phase: 'settled_unverified',
                      settlement_provenance: 'api_legacy_catch_up')
    )
    expect(described_class.catch_up![:settled_intents]).to eq(0)
  end

  it 'settles a completed opaque backup 5204 and clears its DB drain blocker' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    completed = chain(state: :done)
    snapshot = transaction(completed, handle: 5204)
    pending, = opaque_backup_snapshot(completed, snapshot, pool:)
    finish(snapshot)

    expect(StorageFreezeStatus.snapshot).to include(db_drained: false, repair_ready: false)
    expect(described_class.catch_up!).to include(settled_intents: 1,
                                                 settled_chain_ids: [completed.id])
    expect(pending.reload).to have_attributes(phase: 'settled_unverified',
                                              settlement_provenance: 'api_legacy_catch_up')
    expect(StorageFreezeStatus.snapshot).to include(db_drained: true, repair_ready: false)
    expect(described_class.catch_up![:settled_intents]).to eq(0)
  end

  it 'settles a backup 5204 with a complete multi-Pool observer manifest' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    other_pool = create_pool!(node: SpecSeed.node, role: :primary)
    completed = chain(state: :done)
    snapshot = transaction(completed, handle: 5204)
    pending, = opaque_backup_snapshot(completed, snapshot, pool: backup_pool)
    observer_pool_target(pending, other_pool, sequence: 1)
    finish(snapshot)

    result = described_class.catch_up!
    expect(result).to include(scanned_chains: 1, settled_intents: 1,
                              blocked_chain_ids: [])
    expect(pending.reload).to be_settled_unverified
  end

  it 'reports a missing secondary observer target without settling the backup 5204' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    other_pool = create_pool!(node: SpecSeed.node, role: :primary)
    completed = chain(state: :done)
    snapshot = transaction(completed, handle: 5204)
    pending, = opaque_backup_snapshot(completed, snapshot, pool: backup_pool)
    secondary = observer_pool_target(pending, other_pool, sequence: 1)
    finish(snapshot)
    secondary.delete

    result = described_class.catch_up!
    expect(result).to include(scanned_chains: 1, settled_intents: 0,
                              blocked_chain_ids: [completed.id], has_more: false)
    expect(result.fetch(:blocked_reasons).fetch(completed.id))
      .to eq('intent_link_or_physical_phase_unresolved')
    expect(pending.reload).to be_prepared
  end

  it 'reports a malformed-only 5204 page as blocked instead of complete' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    completed = chain(state: :done)
    snapshot = transaction(completed, handle: 5204)
    pending, target = opaque_backup_snapshot(completed, snapshot, pool:)
    finish(snapshot)
    target.update_columns(kind: 'snapshot_create')

    result = described_class.catch_up!
    expect(result).to include(scanned_chains: 1, settled_intents: 0,
                              blocked_chains: 1, blocked_chain_ids: [completed.id],
                              has_more: false, next_after_chain_id: completed.id)
    expect(result.fetch(:blocked_reasons).fetch(completed.id))
      .to eq('intent_link_or_physical_phase_unresolved')
    expect(pending.reload).to be_prepared
    expect(StorageFreezeStatus.snapshot[:db_drained]).to be(false)
  end

  it 'leaves fatal and incomplete opaque backup snapshots prepared' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    completed = chain(state: :fatal)
    snapshot = transaction(completed, handle: 5204)
    pending, = opaque_backup_snapshot(completed, snapshot, pool:)
    finish(snapshot)

    result = described_class.catch_up!
    expect(result.fetch(:blocked_reasons).fetch(completed.id)).to eq('chain_not_terminal')
    completed.update_columns(state: 2)
    snapshot.update_columns(output: nil)
    result = described_class.catch_up!
    expect(result.fetch(:blocked_reasons).fetch(completed.id)).to eq('transaction_result_incomplete')
    expect(pending.reload).to be_prepared
  end

  it 'does not catch up guarded, malformed or unscoped 5204 evidence' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    completed = chain(state: :done)
    snapshot = transaction(completed, handle: 5204)
    pending, target = opaque_backup_snapshot(completed, snapshot, pool:)
    finish(snapshot)

    snapshot.update_columns(input: JSON.parse(snapshot.input).deep_merge(
      'input' => { 'storage_guard' => nil }
    ).to_json)
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    snapshot.update_columns(input: '{}')
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    snapshot.update_columns(input: {
      transaction_chain: completed.id, handle: 5204, node: pool.node_id,
      input: { pool_fs: pool.filesystem }
    }.to_json)
    target.update_columns(kind: 'snapshot_create')
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    target.update_columns(kind: 'observer_unbounded')
    StorageMutationAttempt.create!(
      storage_mutation_intent: pending, command_key: '5204',
      direction: :execute, attempt_number: 1, state: :succeeded
    )
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    StorageMutationAttempt.where(storage_mutation_intent_id: pending.id).delete_all
    target.delete
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    expect(pending.reload).to be_prepared
    expect(StorageFreezeStatus.snapshot[:db_drained]).to be(false)
  end

  it 'requires a unique backup Pool and consistent intent links' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    completed = chain(state: :done)
    snapshot = transaction(completed, handle: 5204)
    pending, = opaque_backup_snapshot(completed, snapshot, pool:)
    finish(snapshot)

    create_pool!(node: SpecSeed.node, role: :primary, filesystem: pool.filesystem)
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    Pool.where(node_id: pool.node_id, filesystem: pool.filesystem)
        .where.not(id: pool.id).delete_all
    StorageMutationIntent.where(id: pending.id).update_all(node_catalog_id: pool.node_id + 1)
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    expect(pending.reload).to be_prepared
  end

  it 'blocks duplicate targets and an intent scope without a target' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    completed = chain(state: :done)
    snapshot = transaction(completed, handle: 5204)
    pending, target = opaque_backup_snapshot(completed, snapshot, pool:)
    finish(snapshot)
    duplicate = StorageMutationTarget.create!(
      storage_mutation_intent: pending,
      storage_mutation_intent_scope: target.storage_mutation_intent_scope,
      command_key: '5204', sequence: 1, kind: 'observer_unbounded'
    )
    expect(described_class.catch_up![:settled_intents]).to eq(0)

    duplicate.delete
    other_pool = create_pool!(node: SpecSeed.node, role: :primary)
    other_scope = StorageIntegrityScope.create!(
      pool: other_pool, scope_key: "pool:#{other_pool.id}",
      state: :unverified, mutation_epoch: 1
    )
    StorageMutationIntentScope.create!(
      storage_mutation_intent: pending, storage_integrity_scope: other_scope,
      expected_epoch: other_scope.mutation_epoch
    )
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    expect(pending.reload).to be_prepared
  end

  it 'blocks another generic intent when the same chain has unresolved 5204 evidence' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    completed = chain(state: :done, size: 2)
    ordinary = transaction(completed)
    ordinary_intent = intent(completed, ordinary)
    snapshot = transaction(completed, handle: 5204)
    _pending, target = opaque_backup_snapshot(completed, snapshot, pool:)
    finish(ordinary)
    finish(snapshot)

    target.update_columns(kind: 'snapshot_create')
    result = described_class.catch_up!
    expect(result.fetch(:blocked_reasons).fetch(completed.id))
      .to eq('intent_link_or_physical_phase_unresolved')
    expect(ordinary_intent.reload).to be_prepared
    target.delete
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    expect(ordinary_intent.reload).to be_prepared
  end

  it 'blocks another generic intent for null 5204 input or a missing transaction link' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    completed = chain(state: :done, size: 2)
    ordinary = transaction(completed)
    ordinary_intent = intent(completed, ordinary)
    snapshot = transaction(completed, handle: 5204)
    pending, = opaque_backup_snapshot(completed, snapshot, pool:)
    finish(ordinary)
    finish(snapshot)
    original_input = snapshot.input

    snapshot.update_columns(input: nil)
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    expect(ordinary_intent.reload).to be_prepared

    snapshot.update_columns(input: original_input)
    StorageMutationIntent.where(id: pending.id).update_all(transaction_id: nil)
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    expect(ordinary_intent.reload).to be_prepared
  end

  it 'refuses a refrozen epoch between catch-up pages' do
    initial_epoch = StorageFreezeControl.singleton!.epoch
    first = chain(state: :done)
    second = chain(state: :done)
    [first, second].each do |member|
      tx = transaction(member)
      intent(member, tx)
      finish(tx)
    end
    observed = 0
    allow(described_class).to receive(:proof_blocker).and_wrap_original do |method, member|
      observed += 1
      StorageFreezeControl.singleton!.update_columns(epoch: initial_epoch + 1) if observed == 1
      method.call(member)
    end

    expect do
      described_class.catch_up!(expected_epoch: initial_epoch)
    end.to raise_error(ArgumentError, /epoch changed/)
    expect(StorageMutationIntent.find_by!(transaction_chain_id: first.id)).to be_settled_unverified
    expect(StorageMutationIntent.find_by!(transaction_chain_id: second.id)).to be_prepared
  end

  it 'requires exact terminal output, skipped follower proof, and all confirmations' do
    completed = chain(state: :failed, size: 2)
    first = transaction(completed)
    second = transaction(completed, handle: 5405)
    first_intent = intent(completed, first)
    finish(first, direction: 'rollback')
    finish(second, status: 'failed', skipped: true)
    confirmation = TransactionConfirmation.create!(
      parent_transaction: first, class_name: 'Dataset', table_name: 'datasets',
      row_pks: { 'id' => 1 }, confirm_type: :edit_after_type, done: 0
    )
    expect(described_class.catch_up![:blocked_chains]).to eq(1)
    expect(first_intent.reload).to be_prepared

    confirmation.update_columns(done: 1)
    expect(described_class.catch_up![:settled_intents]).to eq(1)
    expect(first_intent.reload).to be_settled_unverified
  end

  it 'leaves missing output, fatal chains and started 5204 attempts prepared' do
    completed = chain(state: :done, size: 2)
    generic = transaction(completed)
    snapshot = transaction(completed, handle: 5204)
    generic_intent = intent(completed, generic)
    snapshot_intent = intent(completed, snapshot)
    finish(generic)
    finish(snapshot)
    StorageMutationAttempt.create!(
      storage_mutation_intent: snapshot_intent, command_key: '5204',
      direction: :execute, attempt_number: 1, state: :started
    )
    expect(described_class.catch_up![:settled_intents]).to eq(0)

    StorageMutationAttempt.delete_all
    snapshot_intent.update_columns(phase: 4)
    generic.update_columns(output: nil)
    result = described_class.catch_up!
    expect(result[:settled_intents]).to eq(0)
    expect(result.fetch(:blocked_reasons).fetch(completed.id)).to eq('transaction_result_incomplete')

    finish(generic)
    completed.update_columns(state: 5)
    expect(described_class.catch_up![:settled_intents]).to eq(0)
    expect(generic_intent.reload).to be_prepared
  end

  it 'refuses catch-up when the freeze is not read-only' do
    completed = chain(state: :done)
    tx = transaction(completed)
    intent(completed, tx)
    finish(tx)
    StorageFreezeControl.singleton!.update_columns(mode: 0)

    expect { described_class.catch_up! }.to raise_error(ArgumentError, /read-only/)
  end

  it 'pages past a permanently blocked chain without concealing its ID' do
    blocked = chain(state: :fatal)
    blocked_tx = transaction(blocked)
    intent(blocked, blocked_tx)
    ready = chain(state: :done)
    ready_tx = transaction(ready)
    ready_intent = intent(ready, ready_tx)
    finish(ready_tx)

    first = described_class.catch_up!(limit: 1)
    expect(first).to include(scanned_chains: 1, blocked_chain_ids: [blocked.id],
                             has_more: true, next_after_chain_id: blocked.id)
    expect(first.fetch(:blocked_reasons).fetch(blocked.id)).to eq('chain_not_terminal')

    second = described_class.catch_up!(limit: 1, after_chain_id: first.fetch(:next_after_chain_id))
    expect(second).to include(scanned_chains: 1, settled_intents: 1,
                              blocked_chain_ids: [])
    expect(ready_intent.reload).to be_settled_unverified
  end

  it 'pages past malformed 5204 evidence to a later eligible generic chain' do
    pool = create_pool!(node: SpecSeed.node, role: :backup)
    malformed = chain(state: :done)
    snapshot = transaction(malformed, handle: 5204)
    pending, target = opaque_backup_snapshot(malformed, snapshot, pool:)
    target.update_columns(kind: 'snapshot_create')
    finish(snapshot)

    ready = chain(state: :done)
    generic = transaction(ready)
    ready_intent = intent(ready, generic)
    finish(generic)

    first = described_class.catch_up!(limit: 1)
    expect(first).to include(scanned_chains: 1, blocked_chain_ids: [malformed.id],
                             has_more: true, next_after_chain_id: malformed.id)
    second = described_class.catch_up!(limit: 1,
                                       after_chain_id: first.fetch(:next_after_chain_id))
    expect(second).to include(scanned_chains: 1, settled_intents: 1,
                              settled_chain_ids: [ready.id], blocked_chain_ids: [])
    expect(pending.reload).to be_prepared
    expect(ready_intent.reload).to be_settled_unverified
  end

  it 'reports an oversized chain as a specific blocker without reading all members' do
    oversized = chain(state: :done, size: described_class::MAX_TRANSACTIONS + 1)
    tx = transaction(oversized)
    pending = intent(oversized, tx)
    finish(tx)

    result = described_class.catch_up!
    expect(result.fetch(:blocked_reasons).fetch(oversized.id)).to eq('oversized_chain')
    expect(pending.reload).to be_prepared
  end
end
