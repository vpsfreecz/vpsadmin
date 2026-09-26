# frozen_string_literal: true

require 'spec_helper'

RSpec.describe StorageFreezeStatus do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    StorageFreezeControl.singleton!.update_columns(mode: 1)
  end

  def active_chain(handle: 5004, type: 'TransactionChain')
    chain = TransactionChain.create!(
      name: 'drain_spec', type:, state: :queued,
      size: 1, progress: 0, user: SpecSeed.user, urgent_rollback: false
    )
    Transaction.create!(
      transaction_chain: chain, node: SpecSeed.node, user: SpecSeed.user,
      handle:, queue: 'storage', urgent: false, priority: 0, status: 0,
      input: '{}', reversible: :is_reversible
    )
    chain
  end

  it 'counts a catalog-only NoOp chain by its chain classification' do
    chain = active_chain(handle: 10_001,
                         type: 'TransactionChains::DatasetInPool::DetachBackupHeads')

    status = described_class.snapshot
    expect(status.fetch(:counts)).to include(active_chains: 1, waiting_transactions: 1)
    expect(status.fetch(:sample_chain_ids)).to include(chain.id)
    expect(status[:db_drained]).to be(false)
  end

  it 'blocks on an admitted old untagged writer and reports only DB drain evidence' do
    chain = active_chain(handle: 1001)
    status = described_class.snapshot

    expect(status).to include(mode: 'read_only', db_drained: false,
                              repair_ready: false, stable_epoch: true)
    expect(status.fetch(:counts)).to include(active_chains: 1, waiting_transactions: 1)
    expect(status.fetch(:sample_chain_ids)).to include(chain.id)

    chain.transactions.sole.update_columns(done: 1, status: 1,
                                           output: '{"execute":{"status":"ok"}}',
                                           finished_at: Time.current)
    chain.update_columns(state: 2)
    expect(described_class.snapshot).to include(db_drained: true, repair_ready: false)
  end

  it 'keeps nonterminal intents, uncertain attempts and retained locks visible' do
    chain = active_chain
    tx = chain.transactions.sole
    intent = StorageMutationIntent.create!(
      storage_transaction: tx, transaction_chain: chain, node: SpecSeed.node,
      token: SecureRandom.hex(24), kind: 'observer_dependency',
      protocol_version: 1, manifest_digest: 'b' * 64
    )
    StorageMutationAttempt.create!(
      storage_mutation_intent: intent, command_key: '5004',
      direction: :execute, attempt_number: 1, state: :uncertain
    )
    ResourceLock.create!(resource: 'SpecLock', row_id: 1, locked_by: chain)
    chain.update_columns(state: 5)
    status = described_class.snapshot

    expect(status.fetch(:counts)).to include(prepared_intents: 1,
                                             uncertain_attempts: 1,
                                             retained_chain_locks: 1)
    expect(status[:db_drained]).to be(false)
    expect(status.fetch(:sample_intent_ids)).to include(intent.id)
  end

  it 'blocks fatal and unreviewed resolved chains even after a final rollback' do
    chain = active_chain(handle: 1002)
    chain.update_columns(state: 5)
    expect(described_class.snapshot.fetch(:counts)).to include(
      active_chains: 0, waiting_transactions: 1
    )
    expect(described_class.snapshot[:db_drained]).to be(false)

    chain.update_columns(state: 6)
    expect(described_class.snapshot[:db_drained]).to be(false)

    # NodeCtld uses done=2 for a completed rollback, even though the API enum
    # calls this value "staged". A final rollback is not waiting work.
    chain.transactions.sole.update_columns(done: 2, status: 1,
                                           output: '{"rollback":{"status":"ok"}}',
                                           finished_at: Time.current)
    status = described_class.snapshot
    expect(status.fetch(:counts)).to include(waiting_transactions: 0,
                                             fatal_or_unreviewed_resolved_chains: 1)
    expect(status[:db_drained]).to be(false)
    expect(status.fetch(:sample_fatal_chain_ids)).to include(chain.id)

    chain.update_columns(state: 4)
    expect(described_class.snapshot[:db_drained]).to be(true)
  end

  it 'does not count settled unverified intents as active or claim physical readiness' do
    chain = active_chain
    tx = chain.transactions.sole
    StorageMutationIntent.create!(
      storage_transaction: tx, transaction_chain: chain, node: SpecSeed.node,
      token: SecureRandom.hex(24), kind: 'observer_dependency',
      protocol_version: 1, manifest_digest: 'c' * 64,
      phase: :settled_unverified, settlement_provenance: 'node_chain_close'
    )
    tx.update_columns(done: 1, status: 1, output: '{"execute":{"status":"ok"}}',
                      finished_at: Time.current)
    chain.update_columns(state: 2)
    status = described_class.snapshot

    expect(status.fetch(:counts)).to include(settled_unverified_intents: 1,
                                             prepared_intents: 0)
    expect(status).to include(db_drained: true, repair_ready: false)
  end

  it 'caps more than a thousand settled historical intents without blocking DB drain' do
    now = Time.current
    rows = Array.new(described_class::COUNT_CAP + 1) do
      {
        token: SecureRandom.hex(24), node_catalog_id: SpecSeed.node.id,
        kind: 'observer_dependency', phase: 6, protocol_version: 1,
        manifest_digest: 'c' * 64, settled_at: now,
        settlement_provenance: 'node_chain_close',
        created_at: now, updated_at: now
      }
    end
    StorageMutationIntent.insert_all!(rows)

    status = described_class.snapshot
    expect(status[:counts][:settled_unverified_intents]).to eq(described_class::COUNT_CAP)
    expect(status[:count_capped]).to eq([:settled_unverified_intents])
    expect(status).to include(db_drained: true, repair_ready: false)
  end

  it 'does no DML in status or drain' do
    statements = []
    listener = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] if payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') do
      expect(described_class.snapshot[:db_drained]).to be(true)
      expect(described_class.drain(timeout: 0.01, interval: 0.01)[:db_drained]).to be(true)
    end

    expect(statements.grep(/\A\s*(INSERT|UPDATE|DELETE|REPLACE)\b/i)).to be_empty
  end
end
