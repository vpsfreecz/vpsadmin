# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/storage_mutation_receipt'
require 'nodectld/command'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/snapshot'
require 'nodectld/commands/utils/no_op'

RSpec.describe NodeCtld::StorageMutationReceipt do
  def fixture
    node_id = NodeCtldSpec::BaselineSeed.ids.fetch(:node_id)
    pool = insert_pool!(filesystem: "tank/receipt-#{SecureRandom.hex(3)}")
    dataset_id = sql_insert('datasets', {
      name: '101', full_name: '101', object_state: 0,
      user_create: 1, user_destroy: 1, user_editable: 1
    })
    dip_id = sql_insert('dataset_in_pools', dataset_id:, pool_id: pool.fetch('id'))
    snapshot_id = sql_insert('snapshots', dataset_id:, name: '2026-09-24T12:00:00')
    sip_id = sql_insert('snapshot_in_pools', dataset_in_pool_id: dip_id, snapshot_id:)
    chain_id = insert_chain
    tx_id = insert_transaction(transaction_chain_id: chain_id, handle: 5204)
    now = Time.now.utc
    pool_scope_id = sql_insert('storage_integrity_scopes', {
      pool_id: pool.fetch('id'), pool_catalog_id: pool.fetch('id'),
      scope_key: "pool:#{pool.fetch('id')}", mutation_epoch: 1, state: 0,
      created_at: now, updated_at: now
    })
    scope_id = sql_insert('storage_integrity_scopes', {
      pool_id: pool.fetch('id'), pool_catalog_id: pool.fetch('id'),
      dataset_in_pool_id: dip_id, dataset_in_pool_catalog_id: dip_id,
      scope_key: "dip:#{dip_id}", mutation_epoch: 1, state: 0,
      created_at: now, updated_at: now
    })
    digest = 'd' * 64
    token = SecureRandom.hex(32)
    intent_id = sql_insert('storage_mutation_intents', {
      token:, transaction_chain_id: chain_id, transaction_id: tx_id,
      node_id:, node_catalog_id: node_id, kind: 'snapshot_create',
      phase: 0, protocol_version: 1, manifest_digest: digest,
      created_at: now, updated_at: now
    })
    pool_intent_scope_id = sql_insert('storage_mutation_intent_scopes', {
      storage_mutation_intent_id: intent_id, storage_integrity_scope_id: pool_scope_id,
      expected_epoch: 1, created_at: now, updated_at: now
    })
    intent_scope_id = sql_insert('storage_mutation_intent_scopes', {
      storage_mutation_intent_id: intent_id, storage_integrity_scope_id: scope_id,
      expected_epoch: 1, created_at: now, updated_at: now
    })
    pool_target_id = sql_insert('storage_mutation_targets', {
      storage_mutation_intent_id: intent_id,
      storage_mutation_intent_scope_id: pool_intent_scope_id,
      command_key: '5204', sequence: 0, kind: 'observer_unbounded',
      created_at: now, updated_at: now
    })
    target_id = sql_insert('storage_mutation_targets', {
      storage_mutation_intent_id: intent_id,
      storage_mutation_intent_scope_id: intent_scope_id,
      snapshot_in_pool_id: sip_id, catalog_kind: 'SnapshotInPool', catalog_id: sip_id,
      command_key: '5204', sequence: 1, kind: 'snapshot_create',
      expected_path: "#{pool.fetch('filesystem')}/101@2026-09-24T12:00:00",
      created_at: now, updated_at: now
    })
    {
      guard: { 'token' => token, 'manifest_digest' => digest, 'protocol_version' => 1 },
      trans: { 'id' => tx_id, 'node_id' => node_id, 'transaction_chain_id' => chain_id },
      params: {
        'snapshot_id' => snapshot_id, 'pool_fs' => pool.fetch('filesystem'),
        'dataset_name' => '101', 'planned_snapshot_name' => '2026-09-24T12:00:00'
      },
      intent_id:, intent_scope_id:, scope_id:, target_id:, pool_scope_id:,
      pool_intent_scope_id:, pool_target_id:, pool_id: pool.fetch('id'), dip_id:, sip_id:
    }
  end
  it 'binds a token, writes a started attempt, and saves an immutable GUID receipt' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    attempt = described_class.new(record.fetch(:guard), record.fetch(:trans),
                                  record.fetch(:params), :execute).start!

    expect(sql_row('SELECT state FROM storage_mutation_attempts WHERE id = ?', attempt.id)
             .fetch('state')).to eq(0)
    provenance = sql_row(
      'SELECT strict_dispatch_registry_version, strict_signed_input_digest ' \
      'FROM storage_mutation_attempts WHERE id = ?', attempt.id
    )
    expect(provenance).to include('strict_dispatch_registry_version' => nil,
                                  'strict_signed_input_digest' => nil)
    before = { presence: :missing,
               path: "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00",
               owner_guid: '1001' }
    after = before.merge(presence: :present, guid: '9001')
    shared_db.transaction { |db| attempt.finish!(db, :ok, before, after) }

    expect(sql_row('SELECT state FROM storage_mutation_attempts WHERE id = ?', attempt.id)
             .fetch('state')).to eq(1)
    expect(sql_row('SELECT after_guid FROM storage_mutation_target_observations ' \
                   'WHERE storage_mutation_attempt_id = ?', attempt.id)
             .fetch('after_guid').to_i).to eq(9001)
    rollback = described_class.new(record.fetch(:guard), record.fetch(:trans),
                                   record.fetch(:params), :rollback).start!
    expect(rollback.successful_execute_identity).to eq(
      guid: '9001', owner_guid: '1001',
      path_digest: Digest::SHA256.hexdigest(before.fetch(:path))
    )
    expect do
      described_class.new(record.fetch(:guard), record.fetch(:trans),
                          record.fetch(:params), :execute).start!
    end.to raise_error(described_class::UnsettledAttempt)
    expect(sql_row('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                   record.fetch(:intent_id)).fetch('phase')).to eq(5)

    expect do
      described_class.new(record.fetch(:guard), record.fetch(:trans),
                          record.fetch(:params), :rollback).start!
    end.to raise_error(described_class::UnsettledAttempt)
  end

  it 'binds the planned snapshot name to the full target path before any attempt' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    wrong = record.fetch(:params).merge('planned_snapshot_name' => '2026-09-24T12:00:01')

    expect do
      described_class.new(record.fetch(:guard), record.fetch(:trans), wrong, :execute).start!
    end.to raise_error('storage mutation target does not match snapshot')
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_attempts ' \
                     'WHERE storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(0)
  end

  it 'keeps a needs-reconcile outcome after a later settlement attempt' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    attempt = described_class.new(record.fetch(:guard), record.fetch(:trans),
                                  record.fetch(:params), :execute).start!
    shared_db.transaction do |db|
      attempt.settle!(db, 5)
      attempt.settle!(db, 2)
    end

    expect(sql_row('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                   record.fetch(:intent_id)).fetch('phase')).to eq(5)
    expect(sql_row('SELECT state FROM storage_integrity_scopes WHERE id = ?',
                   sql_row('SELECT storage_integrity_scope_id FROM ' \
                           'storage_mutation_intent_scopes WHERE ' \
                           'storage_mutation_intent_id = ?', record.fetch(:intent_id))
                     .fetch('storage_integrity_scope_id')).fetch('state')).to eq(2)
  end

  it 'quarantines an interrupted attempt when capture fails and never begins rollback' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    attempt = described_class.new(record.fetch(:guard), record.fetch(:trans),
                                  record.fetch(:params), :execute).start!
    command = NodeCtld::Command.new(joined_transaction_row(record.fetch(:trans).fetch('id')))
    handler = instance_double(NodeCtld::Commands::Dataset::Snapshot, output: {})
    allow(handler).to receive(:capture_interrupted_execute_observation)
      .and_raise('injected observation failure')
    allow(handler).to receive(:rollback)
    command.instance_variable_set(:@cmd, handler)
    command.instance_variable_set(:@active_storage_attempt, attempt)

    command.send(:safe_call, described_class.name, :rollback)
    command.save(shared_db)

    expect(handler).not_to have_received(:rollback)

    expect(sql_row('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                   record.fetch(:intent_id)).fetch('phase')).to eq(5)
    expect(sql_row('SELECT state FROM storage_mutation_attempts WHERE id = ?',
                   attempt.id).fetch('state')).to eq(0)
    expect(sql_row('SELECT state FROM transaction_chains WHERE id = ?',
                   sql_row('SELECT transaction_chain_id FROM storage_mutation_intents ' \
                           'WHERE id = ?', record.fetch(:intent_id))
                     .fetch('transaction_chain_id')).fetch('state')).to eq(5)
  end

  %i[before_zfs after_zfs].each do |kill_point|
    it "quarantines a hard kill #{kill_point} without observing or rolling back" do
      record = fixture
      allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
      attempt = described_class.new(record.fetch(:guard), record.fetch(:trans),
                                    record.fetch(:params), :execute).start!
      command = NodeCtld::Command.new(joined_transaction_row(record.fetch(:trans).fetch('id')))
      handler = instance_double(NodeCtld::Commands::Dataset::Snapshot, output: {})
      allow(handler).to receive(:capture_interrupted_execute_observation)
      allow(handler).to receive(:rollback)
      command.instance_variable_set(:@cmd, handler)
      command.instance_variable_set(:@active_storage_attempt, attempt)
      command.instance_variable_set(:@storage_guard, record.fetch(:guard))
      command.instance_variable_set(:@current_method, :exec)

      command.killed(true)
      command.save(shared_db)

      expect(handler).not_to have_received(:capture_interrupted_execute_observation)
      expect(handler).not_to have_received(:rollback)

      expect(sql_row('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id)).fetch('phase')).to eq(5)
      expect(sql_row('SELECT state FROM storage_mutation_attempts WHERE id = ?',
                     attempt.id).fetch('state')).to eq(0)
      expect(sql_value('SELECT COUNT(*) FROM storage_mutation_target_observations ' \
                       'WHERE storage_mutation_attempt_id = ?', attempt.id)).to eq(0)
    end
  end

  it 'quarantines a silent stop/restart interruption before observing ZFS' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    attempt = described_class.new(record.fetch(:guard), record.fetch(:trans),
                                  record.fetch(:params), :execute).start!
    command = NodeCtld::Command.new(joined_transaction_row(record.fetch(:trans).fetch('id')))
    handler = instance_double(NodeCtld::Commands::Dataset::Snapshot, output: {})
    allow(handler).to receive(:capture_interrupted_execute_observation)
    allow(handler).to receive(:rollback)
    command.instance_variable_set(:@cmd, handler)
    command.instance_variable_set(:@active_storage_attempt, attempt)
    command.instance_variable_set(:@storage_guard, record.fetch(:guard))
    command.instance_variable_set(:@current_method, :exec)

    command.killed(false)
    command.save(shared_db)

    expect(handler).not_to have_received(:capture_interrupted_execute_observation)
    expect(handler).not_to have_received(:rollback)

    expect(sql_row('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                   record.fetch(:intent_id)).fetch('phase')).to eq(5)
    expect(sql_row('SELECT state FROM storage_mutation_attempts WHERE id = ?',
                   attempt.id).fetch('state')).to eq(0)
  end

  it 'quarantines failed rollback admission after a committed execute receipt' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    execute = described_class.new(record.fetch(:guard), record.fetch(:trans),
                                  record.fetch(:params), :execute).start!
    path = "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00"
    before = { presence: :missing, path:, owner_guid: '1001' }
    after = before.merge(presence: :present, guid: '9001')
    shared_db.transaction do |db|
      execute.finish!(db, :ok, before, after)
      execute.settle!(db, 2)
    end
    resource_id = insert_cluster_resource_use(value: 10, confirmed: 0)
    tx_id = record.fetch(:trans).fetch('id')
    insert_confirmation(transaction_id: tx_id, class_name: 'ClusterResourceUse',
                        table_name: 'cluster_resource_uses', row_pks: { 'id' => resource_id },
                        confirm_type: 0)
    command = NodeCtld::Command.new(joined_transaction_row(tx_id))
    handler = instance_double(NodeCtld::Commands::Dataset::Snapshot, output: {})
    allow(handler).to receive(:rollback)
    command.instance_variable_set(:@cmd, handler)
    command.instance_variable_set(:@storage_guard, record.fetch(:guard))
    allow(described_class).to receive(:new).and_raise('injected rollback start failure')

    command.send(:safe_call, described_class.name, :rollback)
    command.save(shared_db)

    expect(handler).not_to have_received(:rollback)
    expect(sql_row('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                   record.fetch(:intent_id)).fetch('phase')).to eq(5)
    expect(sql_value('SELECT state FROM storage_integrity_scopes scope ' \
                     'JOIN storage_mutation_intent_scopes linked ' \
                     'ON linked.storage_integrity_scope_id = scope.id ' \
                     'WHERE linked.storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(2)
    expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?',
                     tx_id)).to eq(0)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?',
                     sql_value('SELECT transaction_chain_id FROM storage_mutation_intents ' \
                               'WHERE id = ?', record.fetch(:intent_id)))).to eq(5)
  end

  it 'quarantines a replay when execute receipt lookup fails before a new attempt' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    prior = described_class.new(record.fetch(:guard), record.fetch(:trans),
                                record.fetch(:params), :execute).start!
    resource_id = insert_cluster_resource_use(value: 10, confirmed: 0)
    tx_id = record.fetch(:trans).fetch('id')
    insert_confirmation(transaction_id: tx_id, class_name: 'ClusterResourceUse',
                        table_name: 'cluster_resource_uses', row_pks: { 'id' => resource_id },
                        confirm_type: 0)
    command = NodeCtld::Command.new(joined_transaction_row(tx_id))
    handler = instance_double(NodeCtld::Commands::Dataset::Snapshot, output: {})
    allow(handler).to receive(:exec)
    command.instance_variable_set(:@cmd, handler)
    command.instance_variable_set(:@storage_guard, record.fetch(:guard))
    allow(described_class).to receive(:new).and_raise('injected start SELECT failure')

    command.send(:safe_call, described_class.name, :exec)
    command.save(shared_db)

    expect(handler).not_to have_received(:exec)
    expect(sql_row('SELECT state FROM storage_mutation_attempts WHERE id = ?',
                   prior.id).fetch('state')).to eq(0)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(5)
    expect(sql_value('SELECT state FROM storage_integrity_scopes scope ' \
                     'JOIN storage_mutation_intent_scopes linked ' \
                     'ON linked.storage_integrity_scope_id = scope.id ' \
                     'WHERE linked.storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(2)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?',
                     sql_value('SELECT transaction_chain_id FROM storage_mutation_intents ' \
                               'WHERE id = ?', record.fetch(:intent_id)))).to eq(5)
    expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?',
                     tx_id)).to eq(0)
  end

  it 'rejects a token that is not bound to the command before starting an attempt' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    bad_guard = record.fetch(:guard).merge('manifest_digest' => 'wrong')

    expect do
      described_class.new(bad_guard, record.fetch(:trans),
                          record.fetch(:params), :execute).start!
    end.to raise_error('storage mutation token does not match command')
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_attempts ' \
                     'WHERE storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(0)
  end
end
