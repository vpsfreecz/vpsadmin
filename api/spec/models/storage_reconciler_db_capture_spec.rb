# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::DbCapture do
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
    SpecSeed.pool.update_columns(zpool_guid: BigDecimal('50001'))
    pool = Pool.find(SpecSeed.pool.id)

    capture = described_class.new(pool_id: pool.id, store: nil)
    output = StringIO.new
    capture.instance_variable_set(:@file, output)
    capture.send(:write_record, Pool, pool)
    fields = JSON.parse(output.string).fetch('fields').fetch('fields')
    expect(fields.fetch('zpool_guid')).to eq('50001')

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

      expect(JSON.parse(transaction.input).fetch('input').fetch('zpool_guid')).to eq('50001')
      verify_signature_base64!(transaction.input, transaction.signature)
    ensure
      lock_transaction_signer!
    end
  end

  it 'normalizes exponent-form BigDecimal GUIDs and rejects fractions' do
    row = Struct.new(:id, :zpool_guid, :attributes_before_type_cast).new(
      7, BigDecimal('50001'), { 'id' => 7, 'zpool_guid' => BigDecimal('50001') }
    )
    capture = described_class.new(pool_id: 7, store: nil)
    output = StringIO.new
    capture.instance_variable_set(:@file, output)

    capture.send(:write_record, Pool, row)
    fields = JSON.parse(output.string).fetch('fields').fetch('fields')
    expect(fields.fetch('zpool_guid')).to eq('50001')

    row.zpool_guid = BigDecimal('50001.5')
    expect { capture.send(:write_record, Pool, row) }
      .to raise_error(described_class::Incomplete, 'invalid Pool GUID')
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
