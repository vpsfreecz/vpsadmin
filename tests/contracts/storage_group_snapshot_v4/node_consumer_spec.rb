# frozen_string_literal: true

# This process deliberately does not load libnodectld/spec/spec_helper: that
# helper changes the database name and reloads its schema.
require 'active_record'
require 'bigdecimal'
require 'json'
require 'rspec'
require 'timeout'
require 'uri'
require 'nodectld/confirmations'
require 'nodectld/db'
require 'nodectld/command'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/group_snapshot'
require_relative '../../../libnodectld/spec/support/cfg_helpers'

OsCtl::Lib::Logger.setup(:none)

RSpec.describe NodeCtld::Command do
  let(:manifest) do
    JSON.parse(File.read(File.join(ENV.fetch('CONTRACT_PRIVATE_DIR'), 'producer.json')))
  end

  before do
    url = URI.parse(ENV.fetch('DATABASE_URL'))
    raise 'contract database URL is not private TCP MySQL' unless
      url.scheme == 'mysql2' && url.host == '127.0.0.1' && url.port > 0

    database = url.path.delete_prefix('/')
    port = url.port
    ActiveRecord::Base.establish_connection(ENV.fetch('DATABASE_URL'))
    ActiveRecord::Base.connection.select_value('SELECT 1')
    # The real NodeCtld database and verifier read this process-global config.
    $CFG = NodeCtldSpec::FakeCfg.new( # rubocop:disable Style/GlobalVars
      db: {
        name: database, host: '127.0.0.1', hosts: [],
        user: URI.decode_www_form_component(url.user),
        pass: URI.decode_www_form_component(url.password),
        connect_timeout: 2, read_timeout: 5, write_timeout: 5,
        retry_interval: 1
      },
      vpsadmin: {
        node_id: manifest.fetch('scenarios').first.fetch('node_id'),
        transaction_public_key: manifest.fetch('public_key')
      }
    )

    # NodeCtld::Db has no configured port. Adapt only this example's client
    # construction, after ActiveRecord has connected to the disposable DB.
    allow(Mysql2::Client).to receive(:new).and_wrap_original do |original, opts|
      raise 'Node DB host or name differs from private DB' unless
        opts.fetch(:host) == '127.0.0.1' && opts.fetch(:database) == database
      raise 'Node DB supplied a conflicting port' if opts.has_key?(:port) && opts[:port].to_i != port

      original.call(**opts, port: port)
    end
  rescue URI::InvalidURIError
    raise 'contract database URL is invalid'
  end

  after do
    $CFG = nil # rubocop:disable Style/GlobalVars
    ActiveRecord::Base.connection_pool.disconnect!
  end

  def with_node_db
    Timeout.timeout(30) do
      NodeCtld::Db.open do |db|
        identity = db.query('SELECT @@port AS port, DATABASE() AS db_name').get!
        url = URI.parse(ENV.fetch('DATABASE_URL'))
        expect(identity.fetch('port').to_i).to eq(url.port)
        expect(identity.fetch('db_name')).to eq(url.path.delete_prefix('/'))
        yield db
      end
    end
  end

  def row(db, sql, *args)
    db.prepared(sql, *args).get!
  end

  def count(db, sql, *args)
    row(db, sql, *args).values.first.to_i
  end

  def expect_exact_integer(actual, expected)
    value = BigDecimal(actual.to_s)
    expect(value).to eq(BigDecimal(expected.to_s))
  rescue ArgumentError
    raise RSpec::Expectations::ExpectationNotMetError, 'physical GUID is not a decimal number'
  end

  def producer_row(db, scenario)
    row(db, <<~SQL, scenario.fetch('transaction_id'))
      SELECT t.*, ch.state AS chain_state, ch.progress AS chain_progress,
             ch.size AS chain_size, ch.urgent_rollback AS chain_urgent_rollback
        FROM transactions t
        INNER JOIN transaction_chains ch ON ch.id = t.transaction_chain_id
       WHERE t.id = ?
    SQL
  end

  def verify_producer_contract!(db, scenario)
    trans = producer_row(db, scenario)
    expect(trans.fetch('handle').to_i).to eq(5215)
    expect(trans.fetch('signature')).not_to be_empty
    expect(trans.fetch('node_id').to_i).to eq(scenario.fetch('node_id'))
    expect(trans.fetch('transaction_chain_id').to_i).to eq(scenario.fetch('chain_id'))
    expect(count(db, 'SELECT COUNT(*) FROM resource_locks ' \
                     'WHERE locked_by_type = ? AND locked_by_id = ?',
                 'TransactionChain', scenario.fetch('chain_id'))).to be > 0
    expect(count(db, 'SELECT COUNT(*) FROM transaction_confirmations ' \
                     'WHERE transaction_id = ? AND done = 0',
                 scenario.fetch('transaction_id'))).to be > 0

    actual = []
    db.prepared(<<~SQL, scenario.fetch('intent_id')).each { |item| actual << item }
      SELECT target.id, target.sequence, target.kind, target.expected_path,
             target.expected_owner_fs_guid, target.snapshot_in_pool_id,
             sip.snapshot_id, dip.id AS dip_id, owner.zfs_path AS owner_path,
             owner.zfs_guid AS owner_guid
        FROM storage_mutation_targets target
        LEFT JOIN snapshot_in_pools sip ON sip.id = target.snapshot_in_pool_id
        LEFT JOIN dataset_in_pools dip ON dip.id = sip.dataset_in_pool_id
        LEFT JOIN storage_filesystem_identities owner ON owner.dataset_in_pool_id = dip.id
       WHERE target.storage_mutation_intent_id = ? ORDER BY target.sequence
    SQL
    expect(actual.map { |item| item.fetch('kind') })
      .to eq(%w[observer_unbounded snapshot_create snapshot_create])
    actual.drop(1).zip(scenario.fetch('members')).each do |physical, expected|
      expect(physical.fetch('id').to_i).to eq(expected.fetch('target_id'))
      expect(physical.fetch('snapshot_in_pool_id').to_i).to eq(expected.fetch('sip_id'))
      expect(physical.fetch('snapshot_id').to_i).to eq(expected.fetch('snapshot_id'))
      expect(physical.fetch('dip_id').to_i).to eq(expected.fetch('dip_id'))
      expect(physical.fetch('expected_path')).to eq(expected.fetch('expected_path'))
      expect_exact_integer(physical.fetch('expected_owner_fs_guid'), expected.fetch('owner_guid'))
      expect(physical.fetch('owner_path')).to eq(expected.fetch('expected_path').split('@', 2).first)
      expect_exact_integer(physical.fetch('owner_guid'), expected.fetch('owner_guid'))
    end
    trans
  end

  def fake_physical_effects!(scenario, created:, snapshots:, destroys:)
    members = scenario.fetch('members')
    by_path = members.to_h { |member| [member.fetch('expected_path'), member] }
    inventory = instance_double(NodeCtld::StorageGroupSnapshotReceipt::Inventory)
    allow(inventory).to receive(:observe) do |target|
      member = by_path.fetch(target.fetch(:path))
      expect(target.fetch(:owner_guid)).to eq(member.fetch('owner_guid'))
      observed = {
        path: target.fetch(:path), owner_guid: member.fetch('owner_guid'),
        graph_digest: NodeCtld::StorageGroupSnapshotReceipt::EMPTY_GRAPH_DIGEST,
        empty_dependencies: true
      }
      guid = created[target.fetch(:path)]
      guid ? observed.merge(presence: :present, guid:) : observed.merge(presence: :missing)
    end
    allow(NodeCtld::StorageGroupSnapshotReceipt::Inventory).to receive(:new).and_return(inventory)

    # Command still constructs its real handler; only that instance's ZFS calls are replaced.
    allow(NodeCtld::Commands::Dataset::GroupSnapshot).to receive(:new).and_wrap_original do |original, *args|
      handler = original.call(*args)
      allow(handler).to receive(:zfs) do |action, *zfs_args|
        case action
        when :snapshot
          paths = zfs_args.last.split
          expect(paths).to eq(members.map { |member| member.fetch('expected_path') })
          snapshots.concat(paths)
          paths.each_with_index do |path, index|
            created[path] = (90_000 + (scenario.fetch('chain_id') * 10) + index).to_s
            raise 'injected partial group create' if scenario.fetch('scenario') == 'partial' && index == 0
          end
        when :destroy
          path = zfs_args.last
          expect(created).to have_key(path)
          destroys << path
          created.delete(path)
        else
          raise "unexpected fake ZFS operation #{action}"
        end
      end
      handler
    end
  end

  %w[success partial tampered].each do |name|
    it "checks the real API to Node contract for #{name}" do
      scenario = manifest.fetch('scenarios').find { |item| item.fetch('scenario') == name }
      expect(scenario).not_to be_nil
      with_node_db do |db|
        verify_producer_contract!(db, scenario)
        created = {}
        snapshots = []
        destroys = []
        fake_physical_effects!(scenario, created:, snapshots:, destroys:)

        if name == 'tampered'
          pool_target = row(db, 'SELECT storage_mutation_intent_scope_id ' \
                                'FROM storage_mutation_targets WHERE storage_mutation_intent_id = ? ' \
                                'AND sequence = 0', scenario.fetch('intent_id'))
          db.prepared(
            'INSERT INTO storage_mutation_targets ' \
            '(storage_mutation_intent_id, storage_mutation_intent_scope_id, command_key, ' \
            'sequence, kind, created_at, updated_at) ' \
            'VALUES (?, ?, ?, 3, ?, UTC_TIMESTAMP(), UTC_TIMESTAMP())',
            scenario.fetch('intent_id'), pool_target.fetch('storage_mutation_intent_scope_id'),
            '5215', 'observer_unbounded'
          )
          expect(count(db, 'SELECT COUNT(*) FROM storage_mutation_targets ' \
                           'WHERE storage_mutation_intent_id = ?', scenario.fetch('intent_id'))).to eq(4)
        end

        command = described_class.new(producer_row(db, scenario), strict_storage_dispatch: true)
        Timeout.timeout(30) do
          command.execute
          command.save(db)
        end

        phase = row(db, 'SELECT phase FROM storage_mutation_intents WHERE id = ?',
                    scenario.fetch('intent_id')).fetch('phase').to_i
        chain_state = row(db, 'SELECT state FROM transaction_chains WHERE id = ?',
                          scenario.fetch('chain_id')).fetch('state').to_i
        locks = count(db, 'SELECT COUNT(*) FROM resource_locks ' \
                          'WHERE locked_by_type = ? AND locked_by_id = ?',
                      'TransactionChain', scenario.fetch('chain_id'))
        confirmations = count(db, 'SELECT COUNT(*) FROM transaction_confirmations ' \
                                  'WHERE transaction_id = ? AND done = 0',
                              scenario.fetch('transaction_id'))
        observations = count(db, 'SELECT COUNT(*) FROM storage_mutation_target_observations ' \
                                 'WHERE storage_mutation_attempt_id IN ' \
                                 '(SELECT id FROM storage_mutation_attempts ' \
                                 'WHERE storage_mutation_intent_id = ?)',
                             scenario.fetch('intent_id'))
        signature = row(db, 'SELECT signature FROM transactions WHERE id = ?',
                        scenario.fetch('transaction_id')).fetch('signature')

        case name
        when 'success'
          expect([phase, chain_state, locks, confirmations]).to eq([2, 2, 0, 0])
          expect(observations).to eq(2)
          expect(signature).to be_nil
          expect(created.keys).to match_array(scenario.fetch('members').map { |item| item.fetch('expected_path') })
          expect(snapshots.length).to eq(2)
          expect(destroys).to be_empty
          expect(scenario.fetch('members').map do |member|
            row(db, 'SELECT confirmed FROM snapshots WHERE id = ?', member.fetch('snapshot_id'))
              .fetch('confirmed').to_i
          end).to eq([1, 1])
          expect(scenario.fetch('members').map do |member|
            row(db, 'SELECT confirmed FROM snapshot_in_pools WHERE id = ?', member.fetch('sip_id'))
              .fetch('confirmed').to_i
          end).to eq([1, 1])
        when 'partial'
          expect([phase, chain_state, locks, confirmations]).to eq([3, 4, 0, 0])
          expect(observations).to eq(4)
          expect(signature).to be_nil
          expect(created).to be_empty
          expect(snapshots.length).to eq(2)
          expect(destroys).to eq([scenario.fetch('members').first.fetch('expected_path')])
          scenario.fetch('members').each do |member|
            expect(count(db, 'SELECT COUNT(*) FROM snapshots WHERE id = ?', member.fetch('snapshot_id'))).to eq(0)
            expect(count(db, 'SELECT COUNT(*) FROM snapshot_in_pools WHERE id = ?', member.fetch('sip_id'))).to eq(0)
          end
        when 'tampered'
          expect([phase, chain_state]).to eq([0, 5])
          expect(locks).to be > 0
          expect(confirmations).to be > 0
          expect(observations).to eq(0)
          expect(count(db, 'SELECT COUNT(*) FROM storage_mutation_attempts ' \
                           'WHERE storage_mutation_intent_id = ?', scenario.fetch('intent_id'))).to eq(0)
          expect(snapshots).to be_empty
          expect(destroys).to be_empty
          expect(signature).not_to be_empty
          expect(scenario.fetch('members').map do |member|
            row(db, 'SELECT confirmed FROM snapshots WHERE id = ?', member.fetch('snapshot_id'))
              .fetch('confirmed').to_i
          end).to eq([0, 0])
        end
      end
    end
  end
end
