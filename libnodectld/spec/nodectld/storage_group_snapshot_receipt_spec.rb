# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/confirmations'
require 'nodectld/command'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/group_snapshot'

RSpec.describe NodeCtld::StorageGroupSnapshotReceipt do
  it 'reads one owner depth and binds empty clone, hold and deferred state' do
    inventory = described_class::Inventory.new
    target = {
      owner_path: 'tank/ct/101', path: 'tank/ct/101@2026-09-24T12:00:00',
      owner_guid: '1001'
    }
    allow(inventory).to receive(:zfs).with(
      :list, '-H -t all -d 1 -o name,guid', target.fetch(:owner_path)
    ).and_return(double(output: "tank/ct/101\t1001\ntank/ct/101@2026-09-24T12:00:00\t9001\n"))
    allow(inventory).to receive(:zfs).with(
      :get, '-H -p -o property,value clones,userrefs,defer_destroy', target.fetch(:path)
    ).and_return(double(output: "clones\t-\nuserrefs\t0\ndefer_destroy\toff\n"))

    observed = inventory.observe(target)

    expect(observed).to include(
      presence: :present, guid: '9001', owner_guid: '1001',
      graph_digest: described_class::EMPTY_GRAPH_DIGEST, empty_dependencies: true
    )
    expect(inventory).to have_received(:zfs).with(
      :list, '-H -t all -d 1 -o name,guid', target.fetch(:owner_path)
    )
  end

  it 'treats a failed owner list as unknown and a clone as a rollback blocker' do
    inventory = described_class::Inventory.new
    target = { owner_path: 'tank/ct/101', path: 'tank/ct/101@snap', owner_guid: '1001' }
    allow(inventory).to receive(:zfs).with(
      :list, '-H -t all -d 1 -o name,guid', target.fetch(:owner_path)
    ).and_raise('list unavailable')
    expect { inventory.observe(target) }.to raise_error('list unavailable')

    allow(inventory).to receive(:zfs).with(
      :list, '-H -t all -d 1 -o name,guid', target.fetch(:owner_path)
    ).and_return(double(output: "tank/ct/101\t1001\ntank/ct/101@snap\t9001\n"))
    allow(inventory).to receive(:zfs).with(
      :get, '-H -p -o property,value clones,userrefs,defer_destroy', target.fetch(:path)
    ).and_return(double(output: "clones\ttank/clone\nuserrefs\t0\ndefer_destroy\toff\n"))
    expect(inventory.observe(target)).to include(presence: :present, empty_dependencies: false)
  end

  def fixture
    node_id = NodeCtldSpec::BaselineSeed.ids.fetch(:node_id)
    pool = insert_pool!(filesystem: "tank/group-#{SecureRandom.hex(3)}")
    name = '2026-09-24T12:00:00'
    members = 2.times.map do |index|
      dataset_name = "group-#{index}-#{SecureRandom.hex(3)}"
      dataset_id = sql_insert('datasets', {
        name: dataset_name, full_name: dataset_name, object_state: 0,
        user_create: 1, user_destroy: 1, user_editable: 1
      })
      dip_id = sql_insert('dataset_in_pools', dataset_id:, pool_id: pool.fetch('id'))
      snapshot_id = sql_insert('snapshots', dataset_id:, name: "#{name} (unconfirmed)")
      sip_id = sql_insert('snapshot_in_pools', dataset_in_pool_id: dip_id, snapshot_id:)
      owner_path = "#{pool.fetch('filesystem')}/#{dataset_name}"
      owner_guid = (3000 + index).to_s
      now = Time.now.utc
      sql_insert('storage_filesystem_identities', {
        node_id:, pool_id: pool.fetch('id'), dataset_in_pool_id: dip_id,
        zfs_path: owner_path, path_digest: Digest::SHA256.hexdigest(owner_path),
        zfs_guid: owner_guid.to_i, physical_presence: 1, origin_state: 0,
        created_at: now, updated_at: now
      })
      { dip_id:, sip_id:, snapshot_id:, dataset_name:, owner_guid:,
        owner_path:, path: "#{owner_path}@#{name}" }
    end
    chain_id = insert_chain
    snapshots = members.map do |member|
      { 'pool_fs' => pool.fetch('filesystem'), 'dataset_name' => member.fetch(:dataset_name),
        'snapshot_id' => member.fetch(:snapshot_id) }
    end
    token = SecureRandom.hex(32)
    digest = 'a' * 64
    guard = { 'token' => token, 'manifest_digest' => digest, 'protocol_version' => 1,
              'registry_version' => NodeCtld::StorageEffectRegistry::VERSION }
    payload, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id:, depends_on_id: nil, handle: 5215, node_id:, reversible: 1,
      input: { 'snapshots' => snapshots, 'planned_snapshot_name' => name,
               'storage_guard' => guard }
    )
    tx_id = insert_transaction(transaction_chain_id: chain_id, handle: 5215,
                               input: payload, signature:)
    now = Time.now.utc
    pool_scope_id = sql_insert('storage_integrity_scopes', {
      pool_id: pool.fetch('id'), pool_catalog_id: pool.fetch('id'),
      scope_key: "pool:#{pool.fetch('id')}", mutation_epoch: 1, state: 0,
      created_at: now, updated_at: now
    })
    intent_id = sql_insert('storage_mutation_intents', {
      token:, transaction_chain_id: chain_id, transaction_id: tx_id,
      node_id:, node_catalog_id: node_id, kind: 'snapshot_group_create', phase: 0,
      protocol_version: 1, manifest_digest: digest, created_at: now, updated_at: now
    })
    pool_link_id = sql_insert('storage_mutation_intent_scopes', {
      storage_mutation_intent_id: intent_id, storage_integrity_scope_id: pool_scope_id,
      expected_epoch: 1, created_at: now, updated_at: now
    })
    sql_insert('storage_mutation_targets', {
      storage_mutation_intent_id: intent_id, storage_mutation_intent_scope_id: pool_link_id,
      command_key: '5215', sequence: 0, kind: 'observer_unbounded',
      created_at: now, updated_at: now
    })
    members.each_with_index do |member, index|
      scope_id = sql_insert('storage_integrity_scopes', {
        pool_id: pool.fetch('id'), pool_catalog_id: pool.fetch('id'),
        dataset_in_pool_id: member.fetch(:dip_id),
        dataset_in_pool_catalog_id: member.fetch(:dip_id),
        scope_key: "dip:#{member.fetch(:dip_id)}", mutation_epoch: 1, state: 0,
        created_at: now, updated_at: now
      })
      link_id = sql_insert('storage_mutation_intent_scopes', {
        storage_mutation_intent_id: intent_id, storage_integrity_scope_id: scope_id,
        expected_epoch: 1, created_at: now, updated_at: now
      })
      member[:target_id] = sql_insert('storage_mutation_targets', {
        storage_mutation_intent_id: intent_id, storage_mutation_intent_scope_id: link_id,
        snapshot_in_pool_id: member.fetch(:sip_id), catalog_kind: 'SnapshotInPool',
        catalog_id: member.fetch(:sip_id), command_key: '5215', sequence: index + 1,
        kind: 'snapshot_create', expected_path: member.fetch(:path),
        expected_owner_fs_guid: member.fetch(:owner_guid).to_i,
        created_at: now, updated_at: now
      })
    end
    { tx_id:, chain_id:, intent_id:, pool_id: pool.fetch('id'), guard:, members:,
      payload:, signature: }
  end

  def inventory_for(record, created)
    inventory = instance_double(described_class::Inventory)
    allow(inventory).to receive(:observe) do |target|
      member = record.fetch(:members).find { |item| item.fetch(:path) == target.fetch(:path) }
      base = { path: target.fetch(:path), owner_guid: member.fetch(:owner_guid),
               graph_digest: described_class::EMPTY_GRAPH_DIGEST, empty_dependencies: true }
      if created[target.fetch(:path)]
        base.merge(presence: :present, guid: created.fetch(target.fetch(:path)))
      else
        base.merge(presence: :missing)
      end
    end
    allow(described_class::Inventory).to receive(:new).and_return(inventory)
  end

  def strict_command(record, created, execute_result: :ok, rollback_result: :ok,
                     on_save: nil)
    cmd = NodeCtld::Command.new(joined_transaction_row(record.fetch(:tx_id)),
                                strict_storage_dispatch: true)
    handler = double(output: {})
    allow(handler).to receive(:exec) do
      raise 'group snapshot failed without an effect' if execute_result == :no_effect

      if execute_result == :partial
        created[record.fetch(:members).first.fetch(:path)] = '9001'
        raise 'partial group snapshot command failure'
      end

      record.fetch(:members).each_with_index do |member, index|
        created[member.fetch(:path)] = (9001 + index).to_s
      end
      { ret: :ok }
    end
    allow(handler).to receive(:rollback) do
      created.clear
      { ret: rollback_result }
    end
    allow(handler).to receive(:storage_observation) do |_direction|
      receipt = cmd.strict_group_snapshot_receipt
      [receipt.before, receipt.observe_all!]
    end
    allow(handler).to receive(:on_save) { |db| on_save&.call(db) }
    allow(handler).to receive(:post_save)
    allow(cmd).to receive(:class_from_name).and_return(double(new: handler))
    cmd
  end

  it 'starts before ZFS and closes a complete two-member execute with exact observations' do
    record = fixture
    created = {}
    inventory_for(record, created)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    insert_resource_lock(chain_id: record.fetch(:chain_id))
    cmd = strict_command(record, created)

    cmd.execute
    cmd.save(shared_db)

    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(2)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', record.fetch(:chain_id))).to eq(2)
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_target_observations')).to be >= 2
    expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE locked_by_id = ?', record.fetch(:chain_id))).to eq(0)
    expect(sql_value('SELECT signature FROM transactions WHERE id = ?', record.fetch(:tx_id))).to be_nil
  end

  it 'records and compensates a known partial execute before normal failure closure' do
    record = fixture
    created = {}
    inventory_for(record, created)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    cmd = strict_command(record, created, execute_result: :partial)

    cmd.execute
    cmd.save(shared_db)

    expect(created).to be_empty
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(3)
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_attempts ' \
                     'WHERE storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(2)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', record.fetch(:chain_id))).to eq(4)
  end

  it 'records a proved no-effect group failure as phase four' do
    record = fixture
    created = {}
    inventory_for(record, created)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    cmd = strict_command(record, created, execute_result: :no_effect)

    cmd.execute
    cmd.save(shared_db)

    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(4)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', record.fetch(:chain_id))).to eq(4)
  end

  it 'rejects an embedded group before handler construction or ZFS' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    sql_update('transaction_chains', { size: 2 }, 'id = ?', record.fetch(:chain_id))
    insert_transaction(transaction_chain_id: record.fetch(:chain_id), handle: 10_001,
                       depends_on_id: record.fetch(:tx_id))
    cmd = NodeCtld::Command.new(joined_transaction_row(record.fetch(:tx_id)),
                                strict_storage_dispatch: true)
    allow(cmd).to receive(:class_from_name)

    expect(cmd.execute).to be(false)
    cmd.save(shared_db)

    expect(cmd).not_to have_received(:class_from_name)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(0)
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_attempts ' \
                     'WHERE storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(0)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', record.fetch(:chain_id))).to eq(5)
  end

  it 'keeps logical names pending when terminal proof refuses a tampered target' do
    record = fixture
    created = {}
    inventory_for(record, created)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    insert_resource_lock(chain_id: record.fetch(:chain_id))
    insert_confirmation(transaction_id: record.fetch(:tx_id), class_name: 'SpecRecord',
                        table_name: 'spec_records', row_pks: [1], confirm_type: 0)
    published = []
    cmd = strict_command(record, created, on_save: ->(_db) { published << true })

    cmd.execute
    sql_update('storage_mutation_targets', { expected_path: 'tampered@path' },
               'id = ?', record.fetch(:members).first.fetch(:target_id))
    cmd.save(shared_db)

    expect(published).to be_empty
    expect(sql_value('SELECT name FROM snapshots WHERE id = ?',
                     record.fetch(:members).first.fetch(:snapshot_id)))
      .to end_with(' (unconfirmed)')
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', record.fetch(:chain_id))).to eq(5)
    expect(sql_value('SELECT signature FROM transactions WHERE id = ?', record.fetch(:tx_id)))
      .to eq(record.fetch(:signature))
    expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE locked_by_id = ?', record.fetch(:chain_id))).to eq(1)
    expect(sql_value('SELECT COUNT(*) FROM transaction_confirmations ' \
                     'WHERE transaction_id = ? AND done = 0', record.fetch(:tx_id))).to eq(1)
  end

  it 'rejects old observer wire before constructing a strict handler' do
    record = fixture
    old_payload, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: record.fetch(:chain_id), depends_on_id: nil, handle: 5215,
      node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id), reversible: 1,
      input: { snapshots: [] }
    )
    sql_update('transactions', { input: old_payload, signature: }, 'id = ?', record.fetch(:tx_id))
    cmd = NodeCtld::Command.new(joined_transaction_row(record.fetch(:tx_id)),
                                strict_storage_dispatch: true)
    allow(cmd).to receive(:class_from_name)

    expect(cmd.execute).to be(false)
    cmd.save(shared_db)
    expect(cmd).not_to have_received(:class_from_name)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', record.fetch(:chain_id))).to eq(5)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(0)
  end

  it 'refuses an extra target before any effect or attempt' do
    record = fixture
    created = {}
    inventory_for(record, created)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    now = Time.now.utc
    link_id = sql_value('SELECT storage_mutation_intent_scope_id FROM storage_mutation_targets ' \
                        'WHERE id = ?', record.fetch(:members).first.fetch(:target_id))
    sql_insert('storage_mutation_targets', {
      storage_mutation_intent_id: record.fetch(:intent_id),
      storage_mutation_intent_scope_id: link_id,
      command_key: '5215', sequence: 3, kind: 'observer_unbounded',
      created_at: now, updated_at: now
    })
    cmd = NodeCtld::Command.new(joined_transaction_row(record.fetch(:tx_id)),
                                strict_storage_dispatch: true)
    allow(cmd).to receive(:class_from_name)

    expect(cmd.execute).to be(false)
    cmd.save(shared_db)
    expect(cmd).not_to have_received(:class_from_name)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(0)
    expect(sql_value('SELECT COUNT(*) FROM storage_mutation_attempts ' \
                     'WHERE storage_mutation_intent_id = ?', record.fetch(:intent_id))).to eq(0)
  end

  it 'refuses a missing owner GUID before constructing a handler' do
    record = fixture
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    sql_update('storage_mutation_targets', { expected_owner_fs_guid: nil },
               'id = ?', record.fetch(:members).first.fetch(:target_id))
    cmd = NodeCtld::Command.new(joined_transaction_row(record.fetch(:tx_id)),
                                strict_storage_dispatch: true)
    allow(cmd).to receive(:class_from_name)

    expect(cmd.execute).to be(false)
    cmd.save(shared_db)
    expect(cmd).not_to have_received(:class_from_name)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(0)
  end

  it 'quarantines a prior started group attempt without executing a handler' do
    record = fixture
    created = {}
    inventory_for(record, created)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    trans = joined_transaction_row(record.fetch(:tx_id))
    params, guard, digest = NodeCtld::StorageStrictDispatch.signed_group!(trans)
    described_class.new(guard, trans, params, :execute,
                        signed_input_digest: digest).start!
    cmd = NodeCtld::Command.new(trans, strict_storage_dispatch: true)
    allow(cmd).to receive(:class_from_name)

    expect(cmd.execute).to be(false)
    cmd.save(shared_db)
    expect(cmd).not_to have_received(:class_from_name)
    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(5)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', record.fetch(:chain_id))).to eq(5)
    expect(sql_value('SELECT signature FROM transactions WHERE id = ?', record.fetch(:tx_id)))
      .to eq(record.fetch(:signature))
  end

  it 'keeps a hard-killed started group attempt unresolved' do
    record = fixture
    created = {}
    inventory_for(record, created)
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
    trans = joined_transaction_row(record.fetch(:tx_id))
    params, guard, digest = NodeCtld::StorageStrictDispatch.signed_group!(trans)
    attempt = described_class.new(guard, trans, params, :execute,
                                  signed_input_digest: digest).start!
    cmd = NodeCtld::Command.new(trans, strict_storage_dispatch: true)
    cmd.instance_variable_set(:@storage_guard, guard)
    cmd.instance_variable_set(:@active_storage_attempt, attempt)
    insert_resource_lock(chain_id: record.fetch(:chain_id))

    cmd.killed(true)
    cmd.save(shared_db)

    expect(sql_value('SELECT phase FROM storage_mutation_intents WHERE id = ?', record.fetch(:intent_id))).to eq(5)
    expect(sql_value('SELECT state FROM storage_mutation_attempts WHERE id = ?', attempt.id)).to eq(0)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', record.fetch(:chain_id))).to eq(5)
    expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE locked_by_id = ?', record.fetch(:chain_id))).to eq(1)
  end
end
