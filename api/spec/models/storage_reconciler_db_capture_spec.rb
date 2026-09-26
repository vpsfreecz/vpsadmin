# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::DbCapture do
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
