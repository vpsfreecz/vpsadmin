# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::DbCapture do
  def with_lifetime_rows
    ids = Hash.new { |hash, key| hash[key] = [] }
    yield ids
  ensure
    ResourceLock.where(id: ids[:locks]).delete_all
    TransactionConfirmation.where(id: ids[:confirmations]).delete_all
    StorageMutationTargetObservation.where(id: ids[:observations]).delete_all
    StorageMutationAttempt.where(id: ids[:attempts]).delete_all
    StorageMutationTarget.where(id: ids[:targets]).delete_all
    StorageMutationIntentScope.where(storage_mutation_intent_id: ids[:intents]).delete_all
    StorageMutationIntent.where(id: ids[:intents]).delete_all
    Transaction.where(id: ids[:transactions]).delete_all
    TransactionChain.where(id: ids[:chains]).delete_all
    StorageIntegrityScope.where(id: ids[:scopes]).delete_all
    SnapshotInPoolInBranch.where(id: ids[:sipbs]).delete_all
    Branch.where(id: ids[:branches]).delete_all
    DatasetTree.where(id: ids[:trees]).delete_all
    SnapshotInPool.where(id: ids[:sips]).delete_all
    Snapshot.where(id: ids[:snapshots]).delete_all
    DatasetProperty.where(dataset_in_pool_id: ids[:dips]).delete_all
    DatasetInPool.where(id: ids[:dips]).delete_all
    Dataset.where(id: ids[:datasets]).delete_all
    Pool.where(id: ids[:pools]).delete_all
  end

  def capture_from_database(root:, run_id:, pool:)
    store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id:, create: true)
    [described_class.new(pool_id: pool.id, store:).capture!, store]
  end

  def captured_ids(store, table)
    ids = []
    store.each_line('db.jsonl') do |line|
      fields = JSON.parse(line).fetch('fields')
      ids << fields.fetch('id').to_i if fields.fetch('table') == table
    end
    ids
  end

  def persisted_storage_chain(ids, node:, state:, result:, status:)
    chain = TransactionChain.create!(
      name: 'capture_cost', type: TransactionChains::Vps::Start.name,
      state:, size: 1, progress: 0, user: SpecSeed.user, urgent_rollback: false
    )
    ids[:chains] << chain.id
    transaction = Transaction.create!(
      transaction_chain: chain, node:, user: SpecSeed.user,
      handle: 1001, queue: 'storage', urgent: false, priority: 0,
      status: 0, input: '{"private":"capture cost fixture"}',
      reversible: :is_reversible
    )
    ids[:transactions] << transaction.id
    transaction.update_columns(
      done: 2, status:, output: result.to_json,
      started_at: Time.current, finished_at: Time.current
    )
    [chain, transaction]
  end

  def persistent_intent(ids, node:, phase: :prepared, chain: nil, transaction: nil,
                        node_catalog_id: node&.id)
    intent = StorageMutationIntent.create!(
      token: SecureRandom.hex(24), node:, node_catalog_id:,
      transaction_chain: chain,
      storage_transaction: transaction, kind: 'snapshot_create',
      protocol_version: 1, manifest_digest: 'a' * 64, phase:,
      settled_at: phase == :settled_unverified ? Time.current : nil
    )
    ids[:intents] << intent.id
    intent
  end

  def intent_scope(ids, intent:, pool:)
    scope = StorageIntegrityScope.find_by(scope_key: "pool:#{pool.id}")
    unless scope
      scope = StorageIntegrityScope.create!(pool:, scope_key: "pool:#{pool.id}")
      ids[:scopes] << scope.id
    end
    StorageMutationIntentScope.create!(
      storage_mutation_intent: intent, storage_integrity_scope: scope,
      expected_epoch: scope.mutation_epoch
    )
  end

  def overlap_capture(chain_state:, done: 2, output: '{"rollback":{"status":"ok"}}',
                      status: 1, finished_at: Time.current, chain_size: 1,
                      progress: 0, capture_chain: true, follower: false,
                      follower_started_at: nil)
    chain, transaction, follower_transaction = with_current_context(user: SpecSeed.admin) do
      chain = TransactionChain.create!(
        name: 'db_capture_overlap', type: TransactionChains::Vps::Start.name,
        state: chain_state, size: chain_size,
        progress:, user: SpecSeed.user, urgent_rollback: false
      )
      transaction = Transaction.create!(
        transaction_chain: chain, node: SpecSeed.node, user: SpecSeed.user,
        handle: 1001, queue: 'storage', urgent: false, priority: 0,
        status: 0, input: '{}', reversible: :is_reversible
      )
      transaction.update_columns(done:, status:, output:, finished_at:)
      follower_transaction = if follower
                               Transaction.create!(
                                 transaction_chain: chain, node: SpecSeed.node, user: SpecSeed.user,
                                 handle: 1001, queue: 'storage', urgent: false, priority: 0,
                                 status: 0, input: '{}', reversible: :is_reversible
                               ).tap do |member|
                                 member.update_columns(
                                   done: 1, status: 0,
                                   output: '{"execute":{"status":"failed","skipped":true}}',
                                   started_at: follower_started_at, finished_at: Time.current
                                 )
                               end
                             end
      [chain, transaction, follower_transaction]
    end
    capture = described_class.new(pool_id: SpecSeed.pool.id, store: nil)
    artifact = StringIO.new
    capture.instance_variable_set(:@file, artifact)
    capture.send(:write_record, TransactionChain, chain.reload) if capture_chain
    capture.send(:write_record, Transaction, transaction.reload)
    capture.send(:write_record, Transaction, follower_transaction.reload) if follower_transaction
    [capture, artifact]
  end

  it 'keeps transaction payloads out of the bounded DB artifact' do
    model = Class.new do
      def self.table_name
        'transactions'
      end
    end
    stub_const('Transaction', model)
    row = Struct.new(:id, :attributes_before_type_cast).new(
      7, { 'id' => 7, 'transaction_chain_id' => 9, 'handle' => 5290,
           'input' => 'private signed input', 'output' => 'large result',
           'signature' => 'secret signature' }
    )
    capture = described_class.new(pool_id: 1, store: nil)
    output = StringIO.new
    capture.instance_variable_set(:@file, output)

    capture.send(:write_record, model, row)

    fields = JSON.parse(output.string).fetch('fields').fetch('fields')
    expect(fields).to include('transaction_chain_id' => '9', 'handle' => '5290')
    expect(fields.keys).not_to include('input', 'output', 'signature')
  end

  it 'limits output-bearing SQL pages to 128 rows' do
    capture = described_class.new(pool_id: SpecSeed.pool.id, store: nil)
    capture.instance_variable_set(:@started, Process.clock_gettime(Process::CLOCK_MONOTONIC))
    statements = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      statements << payload.fetch(:sql)
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      capture.send(:emit_relation, Transaction, Transaction.unscoped.where(id: 0))
      capture.send(:emit_relation, TransactionConfirmation,
                   TransactionConfirmation.unscoped.where(id: 0))
    end

    transaction_queries = statements.grep(/FROM `transactions`/i)
    confirmation_queries = statements.grep(/FROM `transaction_confirmations`/i)
    expect(transaction_queries.length).to eq(1)
    expect(confirmation_queries.length).to eq(1)
    expect(transaction_queries + confirmation_queries).to all(match(/LIMIT 128\b/i))
  end

  it 'carries a real DECIMAL Pool GUID as exact digits into signed inventory input' do
    max_guid = '18446744073709551615'
    SpecSeed.pool.update_columns(zpool_guid: BigDecimal(max_guid))
    pool = Pool.find(SpecSeed.pool.id)

    capture = described_class.new(pool_id: pool.id, store: nil)
    output = StringIO.new
    capture.instance_variable_set(:@file, output)
    capture.send(:write_record, Pool, pool)
    fields = JSON.parse(output.string).fetch('fields').fetch('fields')
    expect(fields.fetch('zpool_guid')).to eq(max_guid)

    with_current_context do
      unlock_transaction_signer!
      run_uuid = SecureRandom.uuid
      request = {
        protocol_version: 1, run_uuid:, attempt_uuid: SecureRandom.uuid,
        node_id: pool.node_id, pool_id: pool.id, zpool: pool.name,
        zpool_guid: fields.fetch('zpool_guid'), managed_root: pool.filesystem,
        roots: [pool.filesystem], routing_key: "storage_inventory:#{run_uuid}",
        nonce: SecureRandom.hex(32), deadline: (Time.now.utc + 60).iso8601(6)
      }
      chain, = TransactionChains::Storage::Inventory.fire(request)
      transaction = chain.transactions.sole.reload

      expect(JSON.parse(transaction.input).fetch('input').fetch('zpool_guid')).to eq(max_guid)
      verify_signature_base64!(transaction.input, transaction.signature)
    ensure
      lock_transaction_signer!
    end
  end

  it 'normalizes exponent-form BigDecimal GUIDs and rejects fractions' do
    row = Struct.new(:id, :attributes_before_type_cast).new(
      7, { 'id' => 7, 'zpool_guid' => BigDecimal('50001') }
    )
    capture = described_class.new(pool_id: 7, store: nil)
    output = StringIO.new
    capture.instance_variable_set(:@file, output)

    capture.send(:write_record, Pool, row)
    fields = JSON.parse(output.string).fetch('fields').fetch('fields')
    expect(fields.fetch('zpool_guid')).to eq('50001')

    row.attributes_before_type_cast['zpool_guid'] = BigDecimal('50001.5')
    expect { capture.send(:write_record, Pool, row) }
      .to raise_error(described_class::Incomplete, 'invalid GUID in pools.zpool_guid')
  end

  it 'captures every storage GUID DECIMAL as bounded, plain unsigned digits' do
    columns = {
      Pool => %w[zpool_guid],
      SnapshotInPool => %w[zfs_guid zfs_owner_fs_guid],
      SnapshotInPoolInBranch => %w[zfs_guid zfs_owner_fs_guid],
      StorageFilesystemIdentity => %w[zfs_guid],
      StorageMutationTarget => %w[expected_guid expected_owner_fs_guid],
      StorageMutationTargetObservation => %w[
        before_guid after_guid before_owner_fs_guid after_owner_fs_guid
      ]
    }
    max_guid = '18446744073709551615'

    columns.each do |model, names|
      fields = { 'id' => 7 }.merge(names.to_h { |name| [name, BigDecimal(max_guid)] })
      row = Struct.new(:id, :attributes_before_type_cast).new(7, fields)
      capture = described_class.new(pool_id: 7, store: nil)
      output = StringIO.new
      capture.instance_variable_set(:@file, output)

      capture.send(:write_record, model, row)

      recorded = JSON.parse(output.string).fetch('fields').fetch('fields')
      names.each { |name| expect(recorded.fetch(name)).to eq(max_guid) }

      names.each do |name|
        [BigDecimal('1.5'), BigDecimal('-1'), BigDecimal('18446744073709551616'),
         'NaN', '1e2', 1.0].each do |invalid|
          row.attributes_before_type_cast[name] = invalid
          expect { capture.send(:write_record, model, row) }
            .to raise_error(described_class::Incomplete, "invalid GUID in #{model.table_name}.#{name}")
        end
        row.attributes_before_type_cast[name] = BigDecimal(max_guid)
      end
    end

    capture = described_class.new(pool_id: 7, store: nil)
    ordinary_decimal = BigDecimal('50001')
    expect(capture.send(:normalize, ordinary_decimal)).to eq(ordinary_decimal.to_s)
  end

  it 'does not treat a proved completed rollback as an active chain overlap' do
    output = { execute: { status: 'ok' },
               rollback: { status: 'ok', private: 'terminal rollback private marker' } }.to_json
    capture, artifact = overlap_capture(chain_state: :failed, output:)

    expect(capture.send(:known_chain_overlap?)).to be(false)
    expect(artifact.string).not_to include('terminal rollback private marker')
  end

  it 'keeps staged, rollbacking and fatal chains overlapping despite done=2' do
    %i[staged rollbacking fatal].each do |state|
      capture, = overlap_capture(chain_state: state)
      expect(capture.send(:known_chain_overlap?)).to be(true)
    end
  end

  it 'keeps waiting work and ambiguous terminal rollback records overlapping' do
    cases = [
      { chain_state: :failed, done: 0 },
      { chain_state: :failed, output: nil },
      { chain_state: :failed, output: '{"rollback":{"status":"failed"}}' },
      { chain_state: :failed, finished_at: nil },
      { chain_state: :failed, chain_size: 2 },
      { chain_state: :failed, capture_chain: false }
    ]
    cases.each do |attrs|
      capture, = overlap_capture(**attrs)
      expect(capture.send(:known_chain_overlap?)).to be(true)
    end
  end

  it 'does not accept a skipped retry member that previously started' do
    capture, = overlap_capture(chain_state: :failed, chain_size: 2,
                               follower: true, follower_started_at: Time.current)
    expect(capture.send(:known_chain_overlap?)).to be(true)

    never_started, = overlap_capture(chain_state: :failed, chain_size: 2, follower: true)
    expect(never_started.send(:known_chain_overlap?)).to be(false)
  end

  it 'captures a current unresolved intent despite settled scope history', :no_transaction do
    with_lifetime_rows do |ids|
      pool = Pool.find_by!(filesystem: 'spec_pool_a')
      scope = StorageIntegrityScope.find_by(scope_key: "pool:#{pool.id}")
      unless scope
        scope = StorageIntegrityScope.create!(pool:, scope_key: "pool:#{pool.id}")
        ids[:scopes] << scope.id
      end
      create_intent = lambda do |phase|
        intent = StorageMutationIntent.create!(
          token: SecureRandom.hex(24), node: pool.node,
          kind: 'observer_dependency', protocol_version: 1,
          manifest_digest: 'a' * 64, phase:,
          settled_at: phase == :settled_unverified ? Time.current : nil
        )
        ids[:intents] << intent.id
        StorageMutationIntentScope.create!(
          storage_mutation_intent: intent, storage_integrity_scope: scope,
          expected_epoch: scope.mutation_epoch
        )
        intent
      end
      unresolved = create_intent.call(:prepared)
      unresolved_link = StorageMutationIntentScope.find_by!(storage_mutation_intent_id: unresolved.id)

      Dir.mktmpdir('storage-capture-cost-') do |root|
        baseline, = capture_from_database(root:, run_id: 1, pool:)
        historical = Array.new(12) { create_intent.call(:settled_unverified) }
        expect(StorageMutationIntent.where(id: historical.map(&:id)).settled_unverified.count)
          .to eq(historical.size)
        stub_const("#{described_class}::MAX_ROWS", baseline.fetch('row_count') + 8)

        result = nil
        expect { result = capture_from_database(root:, run_id: 2, pool:) }.not_to raise_error
        summary, store = result
        expect(summary.fetch('pool').fetch('id')).to eq(pool.id.to_s)
        expect(captured_ids(store, 'storage_mutation_intents')).to include(unresolved.id)
        expect(captured_ids(store, 'storage_mutation_intent_scopes')).to include(unresolved_link.id)
      end
    end
  end

  it 'retains an uncertain chain without consuming terminal rollback history', :no_transaction do
    with_lifetime_rows do |ids|
      pool = Pool.find_by!(filesystem: 'spec_pool_a')
      uncertain_chain, uncertain = persisted_storage_chain(
        ids, node: pool.node, state: :fatal,
             result: { rollback: { status: 'failed' } }, status: 0
      )

      Dir.mktmpdir('storage-capture-cost-') do |root|
        baseline, = capture_from_database(root:, run_id: 1, pool:)
        expect(baseline.fetch('known_chain_overlap')).to be(true)
        12.times do |index|
          persisted_storage_chain(
            ids, node: pool.node, state: :failed,
                 result: { rollback: { status: 'ok', private: "history-#{index}" } },
                 status: 1
          )
        end
        expect(Transaction.where(id: ids[:transactions]).where(done: 2).count).to eq(13)
        stub_const("#{described_class}::MAX_ROWS", baseline.fetch('row_count') + 8)

        result = nil
        expect { result = capture_from_database(root:, run_id: 2, pool:) }.not_to raise_error
        summary, store = result
        expect(summary.fetch('known_chain_overlap')).to be(true)
        expect(captured_ids(store, 'transaction_chains')).to include(uncertain_chain.id)
        expect(captured_ids(store, 'transactions')).to include(uncertain.id)
        artifact = File.read(store.path('db.jsonl'))
        expect(artifact).not_to include('capture cost fixture', 'history-0')
      end
    end
  end

  it 'keeps pending off-graph confirmation metadata without private row payload', :no_transaction do
    with_lifetime_rows do |ids|
      pool = Pool.find_by!(filesystem: 'spec_pool_a')
      _chain, transaction = persisted_storage_chain(
        ids, node: pool.node, state: :failed,
             result: { rollback: { status: 'ok' } }, status: 1
      )
      Dir.mktmpdir('storage-capture-confirmation-') do |root|
        _baseline, store = capture_from_database(root:, run_id: 1, pool:)
        baseline_bytes = File.size(store.path('db.jsonl'))
        private_payload = "unrelated-secret-#{'x' * 12_000}"
        confirmation = TransactionConfirmation.create!(
          parent_transaction: transaction, class_name: 'User', table_name: 'users',
          confirm_type: :edit_after_type, done: 0,
          row_pks: { 'id' => SpecSeed.user.id },
          attr_changes: { 'private' => private_payload }
        )
        ids[:confirmations] << confirmation.id
        stub_const("#{described_class}::MAX_ARTIFACT_BYTES", baseline_bytes + 6500)

        summary, captured = capture_from_database(root:, run_id: 2, pool:)
        expect(summary.fetch('known_chain_overlap')).to be(true)
        expect(captured_ids(captured, 'transaction_confirmations')).to include(confirmation.id)
        rows = File.readlines(captured.path('db.jsonl')).map { |line| JSON.parse(line).fetch('fields') }
        fields = rows.find do |row|
          row['table'] == 'transaction_confirmations' && row['id'] == confirmation.id.to_s
        end.fetch('fields')
        expect(fields).to include('transaction_id' => transaction.id.to_s, 'done' => '0')
        expect(fields).not_to have_key('row_pks')
        expect(fields).not_to have_key('attr_changes')
        expect(File.read(captured.path('db.jsonl'))).not_to include(private_payload)
      end
    end
  end

  it 'keeps a terminal writer chain overlapping for a harmless member confirmation', :no_transaction do
    with_lifetime_rows do |ids|
      pool = Pool.find_by!(filesystem: 'spec_pool_a')
      chain = TransactionChain.create!(
        name: 'mixed_confirmation', type: TransactionChains::Vps::Start.name,
        state: :done, size: 2, progress: 2,
        user: SpecSeed.user, urgent_rollback: false
      )
      ids[:chains] << chain.id
      [1001, 5290].each do |handle|
        transaction = Transaction.create!(
          transaction_chain: chain, node: pool.node, user: SpecSeed.user,
          handle:, queue: 'storage', urgent: false, priority: 0,
          status: 0, input: '{}', reversible: :is_reversible
        )
        ids[:transactions] << transaction.id
        transaction.update_columns(
          done: 1, status: 1, output: { execute: { status: 'ok' } }.to_json,
          started_at: Time.current, finished_at: Time.current
        )
      end
      harmless = Transaction.find(ids[:transactions].last)
      private_payload = "private-confirmation-#{'x' * 8000}"
      confirmation = TransactionConfirmation.create!(
        parent_transaction: harmless, class_name: 'User', table_name: 'users',
        confirm_type: :edit_after_type, done: 0,
        row_pks: { 'id' => SpecSeed.user.id },
        attr_changes: { 'private' => private_payload }
      )
      ids[:confirmations] << confirmation.id

      Dir.mktmpdir('storage-capture-mixed-confirmation-') do |root|
        summary, store = capture_from_database(root:, run_id: 1, pool:)
        expect(summary.fetch('known_chain_overlap')).to be(true)
        expect(captured_ids(store, 'transactions')).to include(*ids[:transactions])
        expect(captured_ids(store, 'transaction_confirmations')).to include(confirmation.id)
        expect(File.read(store.path('db.jsonl'))).not_to include(private_payload)
      end
    end
  end

  it 'captures pending SIP FK and copied-ID targets with sibling retries', :no_transaction do
    with_lifetime_rows do |ids|
      pool = Pool.find_by!(filesystem: 'spec_pool_a')
      dataset, dip = create_dataset_with_pool!(
        user: SpecSeed.user, pool:, name: "pending-capture-#{SecureRandom.hex(4)}"
      )
      ids[:datasets] << dataset.id
      ids[:dips] << dip.id
      snapshot, sip = create_snapshot!(dataset:, dip:, confirmed: :confirm_destroy)
      ids[:snapshots] << snapshot.id
      ids[:sips] << sip.id
      settled_snapshot, settled_sip = create_snapshot!(dataset:, dip:)
      ids[:snapshots] << settled_snapshot.id
      ids[:sips] << settled_sip.id
      intent = persistent_intent(ids, node: pool.node, phase: :settled_unverified)
      link = intent_scope(ids, intent:, pool:)
      linked = StorageMutationTarget.create!(
        storage_mutation_intent: intent, storage_mutation_intent_scope: link,
        snapshot_in_pool: sip, command_key: '5204', sequence: 0,
        kind: 'snapshot_create'
      )
      copied = StorageMutationTarget.create!(
        storage_mutation_intent: intent, storage_mutation_intent_scope: link,
        catalog_kind: 'SnapshotInPool', catalog_id: sip.id,
        command_key: '5204', sequence: 1, kind: 'snapshot_create'
      )
      # Preserve the copied-ID/FK disagreement as evidence, even when the FK
      # points to a different, confirmed catalog row.
      copied.update_columns(snapshot_in_pool_id: settled_sip.id)
      ids[:targets].push(linked.id, copied.id)
      prior = StorageMutationAttempt.create!(
        storage_mutation_intent: intent, command_key: '5204',
        attempt_number: 1, direction: :execute, state: :succeeded
      )
      retry_attempt = StorageMutationAttempt.create!(
        storage_mutation_intent: intent, command_key: '5204',
        attempt_number: 1, direction: :rollback, state: :failed
      )
      ids[:attempts].push(prior.id, retry_attempt.id)
      observation = StorageMutationTargetObservation.create!(
        storage_mutation_attempt: retry_attempt,
        storage_mutation_target: copied,
        before_presence: :present, after_presence: :unknown
      )
      ids[:observations] << observation.id

      Dir.mktmpdir('storage-capture-pending-') do |root|
        summary, store = capture_from_database(root:, run_id: 1, pool:)
        expect(summary.fetch('known_chain_overlap')).to be(false)
        expect(captured_ids(store, 'storage_mutation_targets'))
          .to include(linked.id, copied.id)
        expect(captured_ids(store, 'storage_mutation_attempts'))
          .to include(prior.id, retry_attempt.id)
        expect(captured_ids(store, 'storage_mutation_target_observations'))
          .to include(observation.id)

        late_retry = StorageMutationAttempt.create!(
          storage_mutation_intent: intent, command_key: '5204',
          attempt_number: 2, direction: :rollback, state: :uncertain
        )
        ids[:attempts] << late_retry.id
        later, later_store = capture_from_database(root:, run_id: 2, pool:)
        expect(later.fetch('known_chain_overlap')).to be(true)
        expect(captured_ids(later_store, 'storage_mutation_attempts'))
          .to include(prior.id, retry_attempt.id, late_retry.id)
      end
    end
  end

  it 'follows an unconfirmed SIPB even when its SIP and Snapshot are confirmed', :no_transaction do
    with_lifetime_rows do |ids|
      pool = Pool.find_by!(filesystem: 'spec_pool_a')
      dataset, dip = create_dataset_with_pool!(
        user: SpecSeed.user, pool:, name: "pending-sipb-#{SecureRandom.hex(4)}"
      )
      ids[:datasets] << dataset.id
      ids[:dips] << dip.id
      snapshot, sip = create_snapshot!(dataset:, dip:)
      ids[:snapshots] << snapshot.id
      ids[:sips] << sip.id
      tree = create_tree!(dip:)
      branch = create_branch!(tree:, name: 'pending-capture')
      sipb = attach_snapshot_to_branch!(sip:, branch:, confirmed: :confirm_destroy)
      ids[:trees] << tree.id
      ids[:branches] << branch.id
      ids[:sipbs] << sipb.id
      intent = persistent_intent(ids, node: pool.node, phase: :settled_unverified)
      link = intent_scope(ids, intent:, pool:)
      target = StorageMutationTarget.create!(
        storage_mutation_intent: intent, storage_mutation_intent_scope: link,
        catalog_kind: 'SnapshotInPoolInBranch', catalog_id: sipb.id,
        command_key: '5215', sequence: 0, kind: 'snapshot_create'
      )
      ids[:targets] << target.id

      Dir.mktmpdir('storage-capture-sipb-') do |root|
        _summary, store = capture_from_database(root:, run_id: 1, pool:)
        expect(captured_ids(store, 'storage_mutation_targets')).to include(target.id)
        expect(captured_ids(store, 'storage_mutation_intents')).to include(intent.id)
      end
    end
  end

  it 'captures other-Pool node work without that Pool terminal history', :no_transaction do
    with_lifetime_rows do |ids|
      selected = Pool.find_by!(filesystem: 'spec_pool_a')
      other_pool = create_pool!(node: selected.node, role: :primary)
      ids[:pools] << other_pool.id
      pending = persistent_intent(
        ids, node: nil, node_catalog_id: selected.node_id, phase: :prepared
      )
      intent_scope(ids, intent: pending, pool: other_pool)
      unsettled = persistent_intent(ids, node: selected.node, phase: :settled_unverified)
      started = StorageMutationAttempt.create!(
        storage_mutation_intent: unsettled, command_key: '5204',
        attempt_number: 1, direction: :execute, state: :started
      )
      ids[:attempts] << started.id
      historic = persistent_intent(ids, node: selected.node, phase: :settled_unverified)
      intent_scope(ids, intent: historic, pool: other_pool)
      chain = TransactionChain.create!(
        name: 'pending_node_work', type: TransactionChains::Vps::Start.name,
        state: :queued, size: 1, progress: 0,
        user: SpecSeed.user, urgent_rollback: false
      )
      ids[:chains] << chain.id
      transaction = Transaction.create!(
        transaction_chain: chain, node: selected.node, user: SpecSeed.user,
        handle: 2002, queue: 'storage', urgent: false, priority: 0,
        status: 0, input: '{}', reversible: :is_reversible
      )
      ids[:transactions] << transaction.id

      Dir.mktmpdir('storage-capture-node-work-') do |root|
        summary, store = capture_from_database(root:, run_id: 1, pool: selected)
        expect(summary.fetch('known_chain_overlap')).to be(true)
        expect(summary.fetch('historical_terminal_coverage')).to eq('unknown')
        expect(summary.fetch('evidence_selection')).to eq(
          'version' => 1, 'strategy' => 'current_graph_and_observable_node_work',
          'node_ids' => [selected.node_id.to_s],
          'catalog_closure' => 'complete', 'pending_snapshot_evidence' => 'complete',
          'observable_node_work' => 'complete', 'terminal_history' => 'not_enumerated'
        )
        expect(captured_ids(store, 'pools')).to include(other_pool.id)
        expect(captured_ids(store, 'storage_mutation_intents'))
          .to include(pending.id, unsettled.id)
        expect(captured_ids(store, 'storage_mutation_intents')).not_to include(historic.id)
        expect(captured_ids(store, 'storage_mutation_attempts')).to include(started.id)
        expect(captured_ids(store, 'transactions')).to include(transaction.id)
      end
    end
  end

  it 'keeps same-node retained locks and their terminal holders without other-Pool history', :no_transaction do
    with_lifetime_rows do |ids|
      selected = Pool.find_by!(filesystem: 'spec_pool_a')
      other_pool = create_pool!(node: selected.node, role: :primary)
      remote_pool = create_pool!(node: SpecSeed.other_node, role: :primary)
      ids[:pools].push(other_pool.id, remote_pool.id)
      dataset, dip = create_dataset_with_pool!(
        user: SpecSeed.user, pool: other_pool, name: "locked-pool-#{SecureRandom.hex(4)}"
      )
      ids[:datasets] << dataset.id
      ids[:dips] << dip.id
      snapshot, sip = create_snapshot!(dataset:, dip:)
      ids[:snapshots] << snapshot.id
      ids[:sips] << sip.id
      held_chain, held_member = persisted_storage_chain(
        ids, node: selected.node, state: :failed,
             result: { rollback: { status: 'ok' } }, status: 1
      )
      historic_chain, = persisted_storage_chain(
        ids, node: selected.node, state: :failed,
             result: { rollback: { status: 'ok' } }, status: 1
      )
      lock = ResourceLock.create!(resource: 'DatasetInPool', row_id: dip.id, locked_by: held_chain)
      missing_holder = ResourceLock.create!(
        resource: 'Pool', row_id: other_pool.id,
        locked_by_type: 'TransactionChain', locked_by_id: 999_999_999
      )
      remote_lock = ResourceLock.create!(resource: 'Pool', row_id: remote_pool.id)
      ids[:locks].push(lock.id, missing_holder.id, remote_lock.id)

      Dir.mktmpdir('storage-capture-lock-root-') do |root|
        summary, store = capture_from_database(root:, run_id: 1, pool: selected)
        expect(summary.fetch('known_chain_overlap')).to be(true)
        expect(captured_ids(store, 'resource_locks')).to include(lock.id, missing_holder.id)
        expect(captured_ids(store, 'resource_locks')).not_to include(remote_lock.id)
        expect(captured_ids(store, 'transaction_chains')).to include(held_chain.id)
        expect(captured_ids(store, 'transactions')).to include(held_member.id)
        expect(captured_ids(store, 'transaction_chains')).not_to include(historic_chain.id)
        expect(captured_ids(store, 'snapshot_in_pools')).not_to include(sip.id)
      end
    end
  end

  it 'selects exact current scope keys and follows a target-owned foreign scope link', :no_transaction do
    with_lifetime_rows do |ids|
      selected = Pool.find_by!(filesystem: 'spec_pool_a')
      other_pool = create_pool!(node: selected.node, role: :primary)
      ids[:pools] << other_pool.id
      dataset, dip = create_dataset_with_pool!(
        user: SpecSeed.user, pool: selected, name: "scope-closure-#{SecureRandom.hex(4)}"
      )
      ids[:datasets] << dataset.id
      ids[:dips] << dip.id
      snapshot, sip = create_snapshot!(dataset:, dip:, confirmed: :confirm_destroy)
      ids[:snapshots] << snapshot.id
      ids[:sips] << sip.id
      current_scope = StorageIntegrityScope.create!(pool: selected, dataset_in_pool: dip,
                                                    scope_key: "dip:#{dip.id}")
      StorageIntegrityScope.where(id: current_scope.id).update_all(pool_catalog_id: other_pool.id)
      historical_scope = StorageIntegrityScope.create!(
        pool_catalog_id: selected.id, dataset_in_pool_catalog_id: 999_999_998,
        scope_key: 'dip:999999998'
      )
      ids[:scopes].push(current_scope.id, historical_scope.id)
      reached = persistent_intent(ids, node: selected.node, phase: :settled_unverified)
      owner = persistent_intent(ids, node: selected.node, phase: :settled_unverified)
      reached_link = intent_scope(ids, intent: reached, pool: selected)
      foreign_link = StorageMutationIntentScope.create!(
        storage_mutation_intent: owner, storage_integrity_scope: current_scope,
        expected_epoch: current_scope.mutation_epoch
      )
      target = StorageMutationTarget.create!(
        storage_mutation_intent: reached, storage_mutation_intent_scope: reached_link,
        snapshot_in_pool: sip, command_key: '5204', sequence: 0, kind: 'snapshot_create'
      )
      StorageMutationTarget.where(id: target.id)
                           .update_all(storage_mutation_intent_scope_id: foreign_link.id)
      later_intent = persistent_intent(ids, node: selected.node, phase: :settled_unverified)
      later_link = intent_scope(ids, intent: later_intent, pool: selected)
      later_target = StorageMutationTarget.create!(
        storage_mutation_intent: later_intent, storage_mutation_intent_scope: later_link,
        command_key: '5204', sequence: 0, kind: 'observer_unbounded'
      )
      ids[:targets].push(target.id, later_target.id)
      attempt = StorageMutationAttempt.create!(
        storage_mutation_intent: reached, command_key: '5204',
        attempt_number: 1, direction: :execute, state: :succeeded
      )
      ids[:attempts] << attempt.id
      observation = StorageMutationTargetObservation.create!(
        storage_mutation_attempt: attempt, storage_mutation_target: target,
        before_presence: :missing, after_presence: :present
      )
      StorageMutationTargetObservation.where(id: observation.id)
                                      .update_all(storage_mutation_target_id: later_target.id)
      ids[:observations] << observation.id

      Dir.mktmpdir('storage-capture-foreign-link-') do |root|
        _summary, store = capture_from_database(root:, run_id: 1, pool: selected)
        expect(captured_ids(store, 'storage_integrity_scopes')).to include(current_scope.id)
        expect(captured_ids(store, 'storage_integrity_scopes')).not_to include(historical_scope.id)
        expect(captured_ids(store, 'storage_mutation_targets')).to include(target.id, later_target.id)
        expect(captured_ids(store, 'storage_mutation_intent_scopes')).to include(foreign_link.id)
        expect(captured_ids(store, 'storage_mutation_intents'))
          .to include(reached.id, owner.id, later_intent.id)
        expect(captured_ids(store, 'storage_mutation_target_observations'))
          .to include(observation.id)
      end
    end
  end

  it 'does not publish DB evidence when a mandatory budget is exceeded', :no_transaction do
    pool = Pool.find_by!(filesystem: 'spec_pool_a')
    Dir.mktmpdir('storage-capture-cap-') do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      stub_const("#{described_class}::MAX_VISITED_ROWS", 1)

      expect { described_class.new(pool_id: pool.id, store:).capture! }
        .to raise_error(described_class::Incomplete, /visited-row limit/)
      expect(File.exist?(store.path('db.jsonl'))).to be(false)
    end
  end

  it 'does not publish DB evidence when its byte cap is exceeded', :no_transaction do
    pool = Pool.find_by!(filesystem: 'spec_pool_a')
    Dir.mktmpdir('storage-capture-fail-') do |root|
      capped = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      stub_const("#{described_class}::MAX_ARTIFACT_BYTES", 100)
      expect { described_class.new(pool_id: pool.id, store: capped).capture! }
        .to raise_error(described_class::Incomplete, /artifact-byte limit/)
      expect(File.exist?(capped.path('db.jsonl'))).to be(false)
    end
  end

  it 'does not publish DB evidence when a required selector query fails', :no_transaction do
    pool = Pool.find_by!(filesystem: 'spec_pool_a')
    Dir.mktmpdir('storage-capture-fail-') do |root|
      failed = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      capture = described_class.new(pool_id: pool.id, store: failed)
      allow(capture).to receive(:capture_node_work!).and_raise(
        ActiveRecord::StatementInvalid, 'required selector failed'
      )
      expect { capture.capture! }.to raise_error(ActiveRecord::StatementInvalid)
      expect(File.exist?(failed.path('db.jsonl'))).to be(false)
    end
  end

  it 'uses one repeatable-read connection and commits before publishing DB evidence' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      capture = described_class.new(pool_id: 1, store:)
      statements = []
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, transaction_open?: false)
      allow(connection).to receive_messages(select_value: '0', select_one: { 'connection_id' => 17, 'server_time_utc' => Time.utc(2026, 9, 25),
                                                                             'isolation' => 'REPEATABLE-READ' })
      allow(connection).to receive(:execute) do |statement|
        statements << statement
        expect(File.exist?(store.path('db.jsonl'))).to be(false) if statement == 'COMMIT'
      end
      pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool)
      allow(ActiveRecord::Base).to receive(:connection_pool).and_return(pool)
      allow(pool).to receive(:with_connection).and_yield(connection)
      allow(ActiveRecord::Base).to receive(:uncached).and_yield
      allow(capture).to receive(:capture_rows!) do
        rows = Hash.new { |hash, key| hash[key] = {} }
        rows['pools'][1] = { 'id' => '1', 'node_id' => '2',
                             'filesystem' => 'tank/backup', 'role' => '2' }
        rows['storage_integrity_scopes'][3] = { 'scope_key' => 'pool:1', 'mutation_epoch' => '0' }
        rows['storage_freeze_controls'][1] = { 'epoch' => '0' }
        capture.instance_variable_set(:@rows, rows)
      end

      summary = capture.capture!

      expect(statements).to include('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ',
                                    'START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY',
                                    'COMMIT')
      expect(summary.fetch('connection_id')).to eq('17')
      expect(summary.fetch('row_count')).to eq(0)
      expect(File.exist?(store.path('db.jsonl'))).to be(true)
      expect(connection).to have_received(:select_one).at_least(3).times
    end
  end

  it 'never publishes db.jsonl when the read-only transaction cannot commit' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      capture = described_class.new(pool_id: 1, store:)
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, transaction_open?: false)
      allow(connection).to receive(:select_value).with('SELECT @@max_statement_time').and_return('0')
      allow(connection).to receive(:execute) do |statement|
        raise 'commit lost' if statement == 'COMMIT'
      end
      pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool)
      allow(ActiveRecord::Base).to receive(:connection_pool).and_return(pool)
      allow(pool).to receive(:with_connection).and_yield(connection)
      allow(ActiveRecord::Base).to receive(:uncached).and_yield
      allow(capture).to receive(:metadata!).and_return(
        { 'connection_id' => '17', 'server_time_utc' => '2026-09-25T00:00:00.000000Z' }
      )
      allow(capture).to receive(:capture_rows!) do
        capture.instance_variable_get(:@file).write("unpublished\n")
      end

      expect { capture.capture! }.to raise_error('commit lost')
      expect(File.exist?(store.path('db.jsonl'))).to be(false)
      expect(Dir.children(store.run_directory).grep(/db\.jsonl|\.tmp/)).to be_empty
    end
  end
end
