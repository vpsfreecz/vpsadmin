# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/storage_observer_settlement'

RSpec.describe NodeCtld::StorageObserverSettlement do
  def insert_intent(chain_id, tx_id, phase: 0, kind: 'observer_node_pools')
    sql_insert('storage_mutation_intents', {
      token: SecureRandom.hex(24),
      transaction_chain_id: chain_id,
      transaction_id: tx_id,
      node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
      node_catalog_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
      kind: kind,
      phase: phase,
      protocol_version: 1,
      manifest_digest: Digest::SHA256.hexdigest("#{chain_id}:#{tx_id}"),
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    })
  end

  def opaque_backup_snapshot(state: NodeCtldSpec::TxState::CHAIN_DONE, chain_id: nil)
    node_id = NodeCtldSpec::BaselineSeed.ids.fetch(:node_id)
    pool = insert_pool!(role: 2, filesystem: "tank/backup-#{SecureRandom.hex(3)}")
    chain_id ||= insert_chain(state:)
    tx_id = insert_transaction(
      transaction_chain_id: chain_id, handle: 5204,
      input: { transaction_chain: chain_id, handle: 5204, node: node_id,
               input: { pool_fs: pool.fetch('filesystem') } }
    )
    intent_id = insert_intent(chain_id, tx_id, kind: 'snapshot_create')
    scope_id, link_id, target_id = observer_pool_target(intent_id, pool, sequence: 0)
    { pool:, chain_id:, tx_id:, intent_id:, scope_id:, link_id:, target_id: }
  end

  def observer_pool_target(intent_id, pool, sequence:)
    now = Time.now.utc
    scope_id = sql_insert('storage_integrity_scopes', {
      pool_id: pool.fetch('id'), pool_catalog_id: pool.fetch('id'),
      scope_key: "pool:#{pool.fetch('id')}", mutation_epoch: 1, state: 0,
      created_at: now, updated_at: now
    })
    link_id = sql_insert('storage_mutation_intent_scopes', {
      storage_mutation_intent_id: intent_id, storage_integrity_scope_id: scope_id,
      expected_epoch: 1, created_at: now, updated_at: now
    })
    target_id = sql_insert('storage_mutation_targets', {
      storage_mutation_intent_id: intent_id, storage_mutation_intent_scope_id: link_id,
      command_key: '5204', sequence:, kind: 'observer_unbounded',
      created_at: now, updated_at: now
    })
    [scope_id, link_id, target_id]
  end

  def finish(tx_id, direction: 'execute', status: 'ok', skipped: false)
    done = direction == 'rollback' ? 2 : 1
    code = { 'failed' => 0, 'ok' => 1, 'warning' => 2 }.fetch(status)
    output = { direction => { 'status' => status } }
    output.fetch(direction)['skipped'] = true if skipped
    sql_update('transactions', {
      done: done, status: code, output: output.to_json, finished_at: Time.now.utc
    }, 'id = ?', tx_id)
  end

  def settle(chain_id)
    shared_db.transaction { |db| described_class.settle_chain!(db, chain_id) }
  end

  it 'settles all generic intents only after a complete multi-step chain' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_DONE, size: 2)
    tx1 = insert_transaction(transaction_chain_id: chain_id, handle: 5216)
    tx2 = insert_transaction(transaction_chain_id: chain_id, handle: 5405,
                             depends_on_id: tx1)
    ids = [insert_intent(chain_id, tx1), insert_intent(chain_id, tx2)]
    finish(tx1)
    settle(chain_id)
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_intents WHERE phase = 6'))
      .to eq(0)

    finish(tx2)
    settle(chain_id)
    rows = ids.map { |id| sql_row('SELECT phase, settlement_provenance FROM storage_mutation_intents WHERE id = ?', id) }
    expect(rows).to all(include('phase' => 6, 'settlement_provenance' => 'node_chain_close'))
    settle(chain_id)
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_intents WHERE phase = 6'))
      .to eq(2)
  end

  it 'accepts proved rollback and a skipped follower after ordinary failure' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_FAILED, size: 2)
    tx1 = insert_transaction(transaction_chain_id: chain_id, handle: 5216)
    tx2 = insert_transaction(transaction_chain_id: chain_id, handle: 5405,
                             depends_on_id: tx1)
    intent_id = insert_intent(chain_id, tx1)
    finish(tx1, direction: 'rollback')
    finish(tx2, status: 'failed', skipped: true)
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(6)
  end

  it 'retains prepared evidence for fatal, incomplete, or unconfirmed chains' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_FATAL)
    tx_id = insert_transaction(transaction_chain_id: chain_id, handle: 5216)
    intent_id = insert_intent(chain_id, tx_id)
    finish(tx_id)
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(0)

    sql_update('transaction_chains', { state: NodeCtldSpec::TxState::CHAIN_DONE }, 'id = ?', chain_id)
    sql_update('transactions', { output: nil }, 'id = ?', tx_id)
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(0)

    finish(tx_id)
    confirmation_id = insert_confirmation(transaction_id: tx_id, class_name: 'SpecRecord',
                                          table_name: 'spec_records', row_pks: { 'id' => 1 },
                                          confirm_type: 0)
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(0)
    sql_update('transaction_confirmations', { done: 1 }, 'id = ?', confirmation_id)
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(6)
  end

  it 'does not settle generic intents while a 5204 physical attempt is started' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_DONE, size: 2)
    generic_tx = insert_transaction(transaction_chain_id: chain_id, handle: 5216)
    snapshot_tx = insert_transaction(transaction_chain_id: chain_id, handle: 5204,
                                     depends_on_id: generic_tx)
    generic_id = insert_intent(chain_id, generic_tx)
    snapshot_id = insert_intent(chain_id, snapshot_tx)
    finish(generic_tx)
    finish(snapshot_tx)
    sql_insert('storage_mutation_attempts', {
      storage_mutation_intent_id: snapshot_id, command_key: 'snapshot', attempt_number: 1,
      direction: 0, state: 0, started_at: Time.now.utc,
      created_at: Time.now.utc, updated_at: Time.now.utc
    })
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', generic_id)).to eq(0)
  end

  it 'settles an opaque backup 5204 only after normal chain close and stays idempotent' do
    record = opaque_backup_snapshot
    finish(record.fetch(:tx_id))
    settle(record.fetch(:chain_id))
    expect(sql_row('SELECT phase, settlement_provenance FROM storage_mutation_intents WHERE id = ?',
                   record.fetch(:intent_id))).to include(
                     'phase' => 6, 'settlement_provenance' => 'node_chain_close'
                   )
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_intents WHERE phase = 6')).to eq(1)
    expect(sql_value('SELECT state FROM storage_integrity_scopes WHERE id = ?',
                     record.fetch(:scope_id))).to eq(0)
  end

  it 'settles a complete multi-Pool backup observer manifest' do
    record = opaque_backup_snapshot
    other_pool = insert_pool!(filesystem: "tank/other-#{SecureRandom.hex(3)}", role: 1)
    observer_pool_target(record.fetch(:intent_id), other_pool, sequence: 1)
    finish(record.fetch(:tx_id))

    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(6)
  end

  it 'keeps a multi-Pool backup intent prepared when a secondary target is missing' do
    record = opaque_backup_snapshot
    other_pool = insert_pool!(filesystem: "tank/other-#{SecureRandom.hex(3)}", role: 1)
    _scope_id, _link_id, secondary_id = observer_pool_target(
      record.fetch(:intent_id), other_pool, sequence: 1
    )
    finish(record.fetch(:tx_id))
    raw_connection.query("DELETE FROM storage_mutation_targets WHERE id = #{secondary_id}")

    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(0)
  end

  it 'keeps an opaque backup 5204 prepared for fatal and incomplete chains' do
    record = opaque_backup_snapshot(state: NodeCtldSpec::TxState::CHAIN_FATAL)
    finish(record.fetch(:tx_id))
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(0)

    sql_update('transaction_chains', { state: NodeCtldSpec::TxState::CHAIN_DONE },
               'id = ?', record.fetch(:chain_id))
    sql_update('transactions', { output: nil }, 'id = ?', record.fetch(:tx_id))
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(0)
  end

  it 'refuses malformed, unscoped, guarded and receipt-bearing 5204 evidence' do
    record = opaque_backup_snapshot
    finish(record.fetch(:tx_id))
    tx_id = record.fetch(:tx_id)
    intent_id = record.fetch(:intent_id)
    target_id = record.fetch(:target_id)

    sql_update('transactions', { input: '{' }, 'id = ?', tx_id)
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(0)

    input = { transaction_chain: record.fetch(:chain_id), handle: 5204,
              node: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
              input: { pool_fs: record.fetch(:pool).fetch('filesystem'), storage_guard: nil } }
    sql_update('transactions', { input: input.to_json }, 'id = ?', tx_id)
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(0)

    input.fetch(:input).delete(:storage_guard)
    sql_update('transactions', { input: input.to_json }, 'id = ?', tx_id)
    sql_update('storage_mutation_targets', { kind: 'snapshot_create' }, 'id = ?', target_id)
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(0)

    sql_update('storage_mutation_targets', { kind: 'observer_unbounded' }, 'id = ?', target_id)
    sql_insert('storage_mutation_attempts', {
      storage_mutation_intent_id: intent_id, command_key: '5204',
      attempt_number: 1, direction: 0, state: 1,
      created_at: Time.now.utc, updated_at: Time.now.utc
    })
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', intent_id)).to eq(0)
  end

  it 'blocks duplicate or missing target links and a duplicate backup Pool path' do
    record = opaque_backup_snapshot
    finish(record.fetch(:tx_id))
    now = Time.now.utc
    duplicate_id = sql_insert('storage_mutation_targets', {
      storage_mutation_intent_id: record.fetch(:intent_id),
      storage_mutation_intent_scope_id: record.fetch(:link_id),
      command_key: '5204', sequence: 1, kind: 'observer_unbounded',
      created_at: now, updated_at: now
    })
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(0)

    raw_connection.query("DELETE FROM storage_mutation_targets WHERE id = #{duplicate_id}")
    duplicate_pool = insert_pool!(filesystem: record.fetch(:pool).fetch('filesystem'), role: 1)
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(0)
    raw_connection.query("DELETE FROM pools WHERE id = #{duplicate_pool.fetch('id')}")

    other_pool = insert_pool!(filesystem: "tank/other-#{SecureRandom.hex(3)}")
    other_scope_id = sql_insert('storage_integrity_scopes', {
      pool_id: other_pool.fetch('id'), pool_catalog_id: other_pool.fetch('id'),
      scope_key: "pool:#{other_pool.fetch('id')}", mutation_epoch: 1, state: 0,
      created_at: now, updated_at: now
    })
    sql_insert('storage_mutation_intent_scopes', {
      storage_mutation_intent_id: record.fetch(:intent_id),
      storage_integrity_scope_id: other_scope_id, expected_epoch: 1,
      created_at: now, updated_at: now
    })
    settle(record.fetch(:chain_id))
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(0)
  end

  it 'blocks generic chain settlement when another 5204 lacks a valid target' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_DONE, size: 2)
    generic_tx = insert_transaction(transaction_chain_id: chain_id, handle: 5216)
    generic_id = insert_intent(chain_id, generic_tx)
    record = opaque_backup_snapshot(chain_id:)
    finish(generic_tx)
    finish(record.fetch(:tx_id))

    sql_update('storage_mutation_targets', { kind: 'snapshot_create' },
               'id = ?', record.fetch(:target_id))
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', generic_id)).to eq(0)
    raw_connection.query("DELETE FROM storage_mutation_targets WHERE id = #{record.fetch(:target_id)}")
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', generic_id)).to eq(0)
  end

  it 'blocks generic chain settlement for null input and a missing transaction link' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_DONE, size: 2)
    generic_tx = insert_transaction(transaction_chain_id: chain_id, handle: 5216)
    generic_id = insert_intent(chain_id, generic_tx)
    record = opaque_backup_snapshot(chain_id:)
    finish(generic_tx)
    finish(record.fetch(:tx_id))
    original_input = sql_value('SELECT input FROM transactions WHERE id = ?', record.fetch(:tx_id))

    sql_update('transactions', { input: nil }, 'id = ?', record.fetch(:tx_id))
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', generic_id)).to eq(0)

    sql_update('transactions', { input: original_input }, 'id = ?', record.fetch(:tx_id))
    sql_update('storage_mutation_intents', { transaction_id: nil },
               'id = ?', record.fetch(:intent_id))
    settle(chain_id)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', generic_id)).to eq(0)
  end
end
