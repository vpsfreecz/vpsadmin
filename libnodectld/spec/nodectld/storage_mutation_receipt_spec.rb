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

  def strict_fixture
    record = fixture
    now = Time.now.utc
    owner_path = "#{record.fetch(:params).fetch('pool_fs')}/101"
    sql_insert('storage_filesystem_identities', {
      node_id: record.fetch(:trans).fetch('node_id'), pool_id: record.fetch(:pool_id),
      dataset_in_pool_id: record.fetch(:dip_id), zfs_path: owner_path,
      path_digest: Digest::SHA256.hexdigest(owner_path), zfs_guid: 1001,
      physical_presence: 1, origin_state: 0, created_at: now, updated_at: now
    })
    sql_update('storage_mutation_targets', { expected_owner_fs_guid: 1001 },
               'id = ?', record.fetch(:target_id))
    record[:guard]['registry_version'] = NodeCtld::StorageEffectRegistry::VERSION
    sign_strict_transaction!(record)
    record
  end

  def sign_strict_transaction!(record)
    payload, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: record.fetch(:trans).fetch('transaction_chain_id'),
      depends_on_id: nil, handle: 5204,
      node_id: record.fetch(:trans).fetch('node_id'), reversible: 1,
      input: record.fetch(:params).merge('storage_guard' => record.fetch(:guard))
    )
    sql_update('transactions', { input: payload, signature: }, 'id = ?',
               record.fetch(:trans).fetch('id'))
    record[:trans]['input'] = payload
    record[:trans]['signature'] = signature
    record[:trans]['handle'] = 5204
    record[:trans]['depends_on_id'] = nil
    record[:trans]['reversible'] = 1
  end

  def strict_receipt(record, direction)
    described_class.new(
      record.fetch(:guard), record.fetch(:trans),
      record.fetch(:params).merge('storage_guard' => record.fetch(:guard)), direction,
      strict: true,
      strict_signed_input_digest: Digest::SHA256.hexdigest(record.fetch(:trans).fetch('input'))
    )
  end

  def add_harmless_tail!(record)
    chain_id = record.fetch(:trans).fetch('transaction_chain_id')
    first_id = record.fetch(:trans).fetch('id')
    sql_update('transaction_chains', { size: 2 }, 'id = ?', chain_id)
    insert_transaction(transaction_chain_id: chain_id, handle: 10_001,
                       depends_on_id: first_id)
  end

  def save_snapshot_execute!(record, strict: true, before: nil, after: nil, status: :ok)
    path = "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00"
    before ||= { presence: :missing, path:, owner_guid: '1001' }
    after ||= before.merge(presence: :present, guid: '9001')
    handler = double(output: {}, exec: { ret: status })
    allow(handler).to receive(:storage_observation).with(:execute).and_return([before, after])
    allow(handler).to receive(:on_save)
    allow(handler).to receive(:post_save)
    cmd = NodeCtld::Command.new(
      joined_transaction_row(record.fetch(:trans).fetch('id')),
      strict_storage_dispatch: strict
    )
    allow(cmd).to receive(:class_from_name).and_return(double(new: handler))
    cmd.execute
    cmd.save(shared_db)
    cmd
  end

  def save_harmless_tail!(tx_id, status: :ok)
    cmd = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)
    if status == :failed
      handler = double(output: {}, exec: { ret: :failed })
      allow(handler).to receive(:on_save)
      allow(cmd).to receive(:class_from_name).and_return(double(new: handler))
    end
    cmd.execute
    cmd.save(shared_db)
    cmd
  end

  it 'settles an unsigned 5204 observer without strict provenance' do
    record = strict_fixture
    tx_id = record.fetch(:trans).fetch('id')
    sql_update('transactions', { signature: nil }, 'id = ?', tx_id)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)

    save_snapshot_execute!(record, strict: false)

    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(2)
    attempt = sql_row(
      'SELECT state, strict_dispatch_registry_version, strict_signed_input_digest ' \
      'FROM storage_mutation_attempts WHERE storage_mutation_intent_id = ?',
      record.fetch(:intent_id)
    )
    expect(attempt).to include(
      'state' => 1,
      'strict_dispatch_registry_version' => nil,
      'strict_signed_input_digest' => nil
    )
  end

  it 'refuses the same unsigned 5204 before a strict attempt' do
    record = strict_fixture
    tx_id = record.fetch(:trans).fetch('id')
    sql_update('transactions', { signature: nil }, 'id = ?', tx_id)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    command = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)

    expect(command.execute).to be(false)
    command.save(shared_db)

    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_attempts ' \
                     'WHERE storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(0)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(0)
  end

  it 'checks exact SIP, DIP owner and completed execute receipt before strict rollback' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    execute = strict_receipt(record, :execute)
    expect(execute.strict_preflight!).to eq(execute)
    attempt = execute.start!
    provenance = sql_row(
      'SELECT strict_dispatch_registry_version, strict_signed_input_digest ' \
      'FROM storage_mutation_attempts WHERE id = ?', attempt.id
    )
    expect(provenance).to include(
      'strict_dispatch_registry_version' => NodeCtld::StorageEffectRegistry::VERSION,
      'strict_signed_input_digest' => Digest::SHA256.hexdigest(record.fetch(:trans).fetch('input'))
    )
    before = { presence: :missing,
               path: "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00",
               owner_guid: '1001' }
    after = before.merge(presence: :present, guid: '9001')
    shared_db.transaction do |db|
      attempt.finish!(db, :ok, before, after)
      attempt.settle!(db, 2)
    end

    rollback = strict_receipt(record, :rollback)
    expect(rollback.strict_preflight!).to eq(rollback)
    rollback_attempt = rollback.start!
    expect(rollback_attempt.successful_execute_identity).to include(guid: '9001', owner_guid: '1001')
    rollback_provenance = sql_row(
      'SELECT strict_dispatch_registry_version, strict_signed_input_digest ' \
      'FROM storage_mutation_attempts WHERE id = ?', rollback_attempt.id
    )
    expect(rollback_provenance).to include(
      'strict_dispatch_registry_version' => NodeCtld::StorageEffectRegistry::VERSION,
      'strict_signed_input_digest' => Digest::SHA256.hexdigest(record.fetch(:trans).fetch('input'))
    )
    expect { rollback.strict_preflight! }.to raise_error(described_class::UnsettledAttempt)
  end

  it 'refuses strict execution with a null owner or duplicate SIP target' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    make_receipt = lambda do
      strict_receipt(record, :execute)
    end
    sql_update('storage_mutation_targets', { expected_owner_fs_guid: nil },
               'id = ?', record.fetch(:target_id))
    expect { make_receipt.call.strict_preflight! }
      .to raise_error(described_class::BindingRefused, /DIP target is malformed/)
    sql_update('storage_mutation_targets', { expected_owner_fs_guid: 1001 },
               'id = ?', record.fetch(:target_id))
    original = sql_row('SELECT * FROM storage_mutation_targets WHERE id = ?', record.fetch(:target_id))
    extra_target_id = sql_insert('storage_mutation_targets', {
      storage_mutation_intent_id: record.fetch(:intent_id),
      storage_mutation_intent_scope_id: original.fetch('storage_mutation_intent_scope_id'),
      snapshot_in_pool_id: record.fetch(:sip_id), command_key: '5204', sequence: 2,
      kind: 'snapshot_create', expected_path: original.fetch('expected_path'),
      expected_owner_fs_guid: 1001, created_at: Time.now.utc, updated_at: Time.now.utc
    })
    expect { make_receipt.call.strict_preflight! }
      .to raise_error(described_class::BindingRefused, /two exact targets/)
    sql_update('storage_mutation_targets', { snapshot_in_pool_id: nil },
               'id = ?', extra_target_id)
    expect { make_receipt.call.strict_preflight! }
      .to raise_error(described_class::BindingRefused, /two exact targets/)
  end

  %i[null_owner duplicate_target extra_observer_target missing_pool_target
     wrong_pool_target wrong_pool_scope wrong_dip_link wrong_snapshot_catalog].each do |defect|
    it "refuses a strict #{defect} binding without quarantining an untouched snapshot" do
      record = strict_fixture
      allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
      sign_strict_transaction!(record)
      tx_id = record.fetch(:trans).fetch('id')
      chain_id = record.fetch(:trans).fetch('transaction_chain_id')
      signature = sql_value('SELECT signature FROM transactions WHERE id = ?', tx_id)
      insert_resource_lock(chain_id:)
      insert_confirmation(transaction_id: tx_id, class_name: 'SpecRecord',
                          table_name: 'spec_records', row_pks: [1], confirm_type: 0)

      case defect
      when :null_owner
        sql_update('storage_mutation_targets', { expected_owner_fs_guid: nil },
                   'id = ?', record.fetch(:target_id))
      when :duplicate_target
        sql_insert('storage_mutation_targets', {
          storage_mutation_intent_id: record.fetch(:intent_id),
          storage_mutation_intent_scope_id: record.fetch(:intent_scope_id),
          snapshot_in_pool_id: record.fetch(:sip_id), command_key: '5204', sequence: 2,
          kind: 'snapshot_create',
          expected_path: "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00",
          expected_owner_fs_guid: 1001,
          created_at: Time.now.utc, updated_at: Time.now.utc
        })
      when :extra_observer_target
        sql_insert('storage_mutation_targets', {
          storage_mutation_intent_id: record.fetch(:intent_id),
          storage_mutation_intent_scope_id: record.fetch(:intent_scope_id),
          command_key: '5204', sequence: 2, kind: 'observer_unbounded',
          created_at: Time.now.utc, updated_at: Time.now.utc
        })
      when :missing_pool_target
        shared_db.prepared('DELETE FROM storage_mutation_targets WHERE id = ?',
                           record.fetch(:pool_target_id))
      when :wrong_pool_target
        sql_update('storage_mutation_targets', { expected_path: 'unexpected@path' },
                   'id = ?', record.fetch(:pool_target_id))
      when :wrong_pool_scope
        other_pool = insert_pool!(filesystem: "tank/other-#{SecureRandom.hex(3)}")
        sql_update('storage_integrity_scopes', { pool_id: other_pool.fetch('id') },
                   'id = ?', record.fetch(:pool_scope_id))
      when :wrong_dip_link
        sql_update('storage_mutation_targets', {
          storage_mutation_intent_scope_id: record.fetch(:pool_intent_scope_id)
        }, 'id = ?', record.fetch(:target_id))
      when :wrong_snapshot_catalog
        sql_update('storage_mutation_targets', { catalog_id: record.fetch(:sip_id) + 1 },
                   'id = ?', record.fetch(:target_id))
      end

      cmd = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)
      allow(cmd).to receive(:class_from_name)
      expect(cmd.execute).to be(false)
      cmd.save(shared_db)

      expect(cmd).not_to have_received(:class_from_name)
      expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                       record.fetch(:intent_id))).to eq(0)
      expect(sql_value('SELECT state FROM storage_integrity_scopes WHERE id = ?',
                       record.fetch(:scope_id))).to eq(0)
      expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(5)
      expect(sql_value('SELECT signature FROM transactions WHERE id = ?', tx_id)).to eq(signature)
      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE locked_by_id = ?', chain_id)).to eq(1)
      expect(sql_value('SELECT COUNT(*) FROM transaction_confirmations ' \
                       'WHERE transaction_id = ? AND done = 0', tx_id)).to eq(1)
      expect(sql_value('SELECT COUNT(*) FROM storage_mutation_attempts ' \
                       'WHERE storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(0)
    end
  end

  it 'quarantines a strict replay with a persisted started attempt' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    sign_strict_transaction!(record)
    tx_id = record.fetch(:trans).fetch('id')
    attempt = strict_receipt(record, :execute).start!
    cmd = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)
    allow(cmd).to receive(:class_from_name)

    expect(cmd.execute).to be(false)
    cmd.save(shared_db)

    expect(cmd).not_to have_received(:class_from_name)
    expect(sql_value('SELECT state FROM storage_mutation_attempts WHERE id = ?', attempt.id)).to eq(0)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(5)
    expect(sql_value('SELECT state FROM storage_integrity_scopes WHERE id = ?',
                     record.fetch(:scope_id))).to eq(2)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?',
                     record.fetch(:trans).fetch('transaction_chain_id'))).to eq(5)
  end

  it 'quarantines a strict snapshot when intent SELECT fails before dispatch' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    sign_strict_transaction!(record)
    tx_id = record.fetch(:trans).fetch('id')
    first_read = true
    allow(NodeCtld::DbTransaction).to receive(:new).and_wrap_original do |original, *args|
      transaction = original.call(*args)
      allow(transaction).to receive(:prepared).and_wrap_original do |prepared, *query_args|
        if first_read && query_args.first.include?('FROM storage_mutation_intents') &&
           query_args.first.include?('WHERE token = ?')
          first_read = false
          raise 'intent SELECT unavailable'
        end

        prepared.call(*query_args)
      end
      transaction
    end
    cmd = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)
    allow(cmd).to receive(:class_from_name)

    expect(cmd.execute).to be(false)
    expect(first_read).to be(false)
    cmd.save(shared_db)

    expect(cmd).not_to have_received(:class_from_name)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(5)
    expect(sql_value('SELECT state FROM storage_integrity_scopes WHERE id = ?',
                     record.fetch(:scope_id))).to eq(2)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?',
                     record.fetch(:trans).fetch('transaction_chain_id'))).to eq(5)
  end

  it 'does not compensate a strict execute failure without a committed execute receipt' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    tx_id = record.fetch(:trans).fetch('id')
    sign_strict_transaction!(record)
    cmd = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)
    handler = double(output: {})
    allow(handler).to receive(:exec).and_raise('injected execute failure')
    allow(handler).to receive(:rollback)
    path = "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00"
    before = { presence: :missing, path:, owner_guid: '1001' }
    allow(handler).to receive(:storage_observation).with(:execute).and_return([before, before])
    allow(cmd).to receive(:class_from_name).and_return(double(new: handler))

    cmd.execute
    cmd.save(shared_db)

    expect(handler).not_to have_received(:rollback)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(5)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?',
                     record.fetch(:trans).fetch('transaction_chain_id'))).to eq(5)
  end

  it 'runs a valid strict 5204 execute and later rollback with distinct receipts' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    sign_strict_transaction!(record)
    chain_id = record.fetch(:trans).fetch('transaction_chain_id')
    tx_id = record.fetch(:trans).fetch('id')
    sql_update('transaction_chains', { size: 2 }, 'id = ?', chain_id)
    tail_id = insert_transaction(transaction_chain_id: chain_id, handle: 10_001,
                                 depends_on_id: tx_id, done: 1, status: 1)
    sql_update('transactions', {
      output: { execute: { status: 'ok' } }.to_json, finished_at: Time.now.utc
    }, 'id = ?', tail_id)
    path = "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00"
    missing = { presence: :missing, path:, owner_guid: '1001' }
    present = missing.merge(presence: :present, guid: '9001')
    handler = double(output: {}, exec: { ret: :ok }, rollback: { ret: :ok })
    allow(handler).to receive(:storage_observation).with(:execute).and_return([missing, present])
    allow(handler).to receive(:storage_observation).with(:rollback).and_return([present, missing])
    allow(handler).to receive(:on_save)
    allow(handler).to receive(:post_save)

    execute = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)
    allow(execute).to receive(:class_from_name).and_return(double(new: handler))
    execute.execute
    execute.save(shared_db)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(2)

    sql_update('transaction_chains', { state: 3, progress: 0 }, 'id = ?', chain_id)
    rollback = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)
    allow(rollback).to receive(:class_from_name).and_return(double(new: handler))
    rollback.execute
    rollback.save(shared_db)

    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(3)
    expect(sql_rows('SELECT direction, state FROM storage_mutation_attempts ' \
                    'WHERE storage_mutation_intent_id = ? ORDER BY direction',
                    record.fetch(:intent_id))).to contain_exactly(
                      include('direction' => 0, 'state' => 1),
                      include('direction' => 1, 'state' => 1)
                    )
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(4)
  end

  it 'refuses rollback before ZFS when the prior execute observation digest changed' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    add_harmless_tail!(record)
    save_snapshot_execute!(record)
    chain_id = record.fetch(:trans).fetch('transaction_chain_id')
    tx_id = record.fetch(:trans).fetch('id')
    insert_resource_lock(chain_id:)
    sql_update('storage_mutation_target_observations', { after_guid: 9002 },
               'storage_mutation_target_id = ?', record.fetch(:target_id))
    sql_update('transaction_chains', { state: 3, progress: 0 }, 'id = ?', chain_id)
    rollback = NodeCtld::Command.new(joined_transaction_row(tx_id),
                                     strict_storage_dispatch: true)
    allow(rollback).to receive(:class_from_name)

    expect(rollback.execute).to be(false)
    rollback.save(shared_db)

    expect(rollback).not_to have_received(:class_from_name)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(5)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(5)
    expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE locked_by_id = ?', chain_id)).to eq(1)
  end

  it 'closes a sole strictly guarded 5204 after its exact execute receipt' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    sign_strict_transaction!(record)
    tx_id = record.fetch(:trans).fetch('id')
    path = "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00"
    missing = { presence: :missing, path:, owner_guid: '1001' }
    present = missing.merge(presence: :present, guid: '9001')
    handler = double(output: {}, exec: { ret: :ok })
    allow(handler).to receive(:storage_observation).with(:execute).and_return([missing, present])
    allow(handler).to receive(:on_save)
    allow(handler).to receive(:post_save)
    command = NodeCtld::Command.new(joined_transaction_row(tx_id), strict_storage_dispatch: true)
    allow(command).to receive(:class_from_name).and_return(double(new: handler))

    command.execute
    command.save(shared_db)

    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(2)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?',
                     record.fetch(:trans).fetch('transaction_chain_id'))).to eq(2)
    expect(sql_value('SELECT signature FROM transactions WHERE id = ?', tx_id)).to be_nil
  end

  %i[ok failed].each do |tail_status|
    it "closes an earlier strict snapshot after a harmless #{tail_status} tail" do
      record = strict_fixture
      allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
      tail_id = add_harmless_tail!(record)
      chain_id = record.fetch(:trans).fetch('transaction_chain_id')
      insert_resource_lock(chain_id:)
      save_snapshot_execute!(record)
      expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(1)

      save_harmless_tail!(tail_id, status: tail_status)

      expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id))
        .to eq(tail_status == :ok ? 2 : 4)
      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE locked_by_id = ?', chain_id)).to eq(0)
      expect(sql_value('SELECT signature FROM transactions WHERE id = ?',
                       record.fetch(:trans).fetch('id'))).to be_nil
      expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                       record.fetch(:intent_id))).to eq(2)
    end
  end

  it 'closes a proved no-effect strict snapshot as an ordinary failed chain' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    path = "#{record.fetch(:params).fetch('pool_fs')}/101@2026-09-24T12:00:00"
    existing = { presence: :present, path:, guid: '9001', owner_guid: '1001' }

    save_snapshot_execute!(record, before: existing, after: existing, status: :failed)

    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(4)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?',
                     record.fetch(:trans).fetch('transaction_chain_id'))).to eq(4)
  end

  %i[observer_phase2 null_marker resigned_input duplicate_target duplicate_attempt
     started_attempt wrong_observation wrong_phase missing_observation
     changed_pool_target changed_pool_scope changed_snapshot_catalog].each do |defect|
    it "refuses an earlier snapshot with #{defect} instead of confirming the tail" do
      record = strict_fixture
      allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
      tail_id = add_harmless_tail!(record)
      chain_id = record.fetch(:trans).fetch('transaction_chain_id')
      first_id = record.fetch(:trans).fetch('id')
      insert_resource_lock(chain_id:)
      insert_confirmation(transaction_id: first_id, class_name: 'SpecRecord',
                          table_name: 'spec_records', row_pks: [1], confirm_type: 0)
      save_snapshot_execute!(record, strict: defect != :observer_phase2)
      attempt = sql_row('SELECT * FROM storage_mutation_attempts ' \
                        'WHERE storage_mutation_intent_id = ?', record.fetch(:intent_id))

      case defect
      when :null_marker
        sql_update('storage_mutation_attempts', {
          strict_dispatch_registry_version: nil, strict_signed_input_digest: nil
        }, 'id = ?', attempt.fetch('id'))
      when :resigned_input
        payload = JSON.parse(record.fetch(:trans).fetch('input'))
        changed = JSON.pretty_generate(payload)
        sql_update('transactions', {
          input: changed, signature: NodeCtldSpec::SigningHelpers.sign_base64(changed)
        }, 'id = ?', first_id)
      when :duplicate_target
        original = sql_row('SELECT * FROM storage_mutation_targets WHERE id = ?',
                           record.fetch(:target_id))
        sql_insert('storage_mutation_targets', {
          storage_mutation_intent_id: record.fetch(:intent_id),
          storage_mutation_intent_scope_id: record.fetch(:intent_scope_id),
          snapshot_in_pool_id: record.fetch(:sip_id), command_key: '5204', sequence: 2,
          kind: 'snapshot_create', expected_path: original.fetch('expected_path'),
          expected_owner_fs_guid: 1001, created_at: Time.now.utc, updated_at: Time.now.utc
        })
      when :duplicate_attempt, :started_attempt
        sql_insert('storage_mutation_attempts', {
          storage_mutation_intent_id: record.fetch(:intent_id), command_key: '5204',
          attempt_number: defect == :duplicate_attempt ? 2 : 1,
          direction: defect == :duplicate_attempt ? 0 : 1, state: 0,
          created_at: Time.now.utc, updated_at: Time.now.utc
        })
      when :wrong_observation
        sql_update('storage_mutation_target_observations', { after_guid: 9002 },
                   'storage_mutation_attempt_id = ?', attempt.fetch('id'))
      when :wrong_phase
        sql_update('storage_mutation_intents', { phase: 4 },
                   'id = ?', record.fetch(:intent_id))
      when :missing_observation
        shared_db.prepared('DELETE FROM storage_mutation_target_observations ' \
                           'WHERE storage_mutation_attempt_id = ?', attempt.fetch('id'))
      when :changed_pool_target
        sql_update('storage_mutation_targets', { expected_path: 'unexpected@path' },
                   'id = ?', record.fetch(:pool_target_id))
      when :changed_pool_scope
        other_pool = insert_pool!(filesystem: "tank/other-#{SecureRandom.hex(3)}")
        sql_update('storage_integrity_scopes', { pool_id: other_pool.fetch('id') },
                   'id = ?', record.fetch(:pool_scope_id))
      when :changed_snapshot_catalog
        sql_update('storage_mutation_targets', { catalog_id: record.fetch(:sip_id) + 1 },
                   'id = ?', record.fetch(:target_id))
      end

      save_harmless_tail!(tail_id)

      expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(5)
      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE locked_by_id = ?', chain_id)).to eq(1)
      expect(sql_value('SELECT COUNT(*) FROM transaction_confirmations ' \
                       'WHERE transaction_id = ? AND done = 0', first_id)).to eq(1)
      expect(sql_value('SELECT signature FROM transactions WHERE id = ?', first_id)).not_to be_nil
    end
  end

  it 'leaves a strict hard-killed started attempt unresolved and closes fatal' do
    record = strict_fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    attempt = strict_receipt(record, :execute).start!
    cmd = NodeCtld::Command.new(joined_transaction_row(record.fetch(:trans).fetch('id')),
                                strict_storage_dispatch: true)
    cmd.instance_variable_set(:@storage_guard, record.fetch(:guard))
    cmd.instance_variable_set(:@active_storage_attempt, attempt)
    cmd.killed(true)
    cmd.save(shared_db)

    expect(sql_value('SELECT state FROM storage_mutation_attempts WHERE id = ?', attempt.id)).to eq(0)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?',
                     record.fetch(:intent_id))).to eq(5)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?',
                     record.fetch(:trans).fetch('transaction_chain_id'))).to eq(5)
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
