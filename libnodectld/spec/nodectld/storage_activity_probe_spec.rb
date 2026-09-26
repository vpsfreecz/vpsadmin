# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/storage_activity_probe'
require 'nodectld/transaction_verifier'
require 'nodectld/queues'
require 'nodectld/daemon'

RSpec.describe NodeCtld::StorageActivityProbe do
  def node_id
    NodeCtldSpec::BaselineSeed.ids.fetch(:node_id)
  end

  def pool
    @pool ||= insert_pool!(filesystem: "tank/activity-#{SecureRandom.hex(3)}")
  end

  def claims
    [{ 'pool_id' => pool.fetch('id').to_i, 'managed_root' => pool.fetch('filesystem'),
       'zpool' => 'tank', 'zpool_guid' => nil }]
  end
  let(:params) do
    {
      protocol_version: 1, request_uuid: SecureRandom.uuid,
      attempt_uuid: SecureRandom.uuid, nonce: SecureRandom.hex(32),
      node_id:, freeze_epoch: 7, deadline: (Time.now.utc + 30).iso8601(6),
      claims:
    }
  end
  let(:trans) do
    input, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: 123, depends_on_id: nil, handle: 5291, node_id:,
      reversible: 0, input: params
    )
    { 'id' => 567, 'transaction_chain_id' => 123, 'depends_on_id' => nil,
      'handle' => 5291, 'node_id' => node_id, 'input' => input,
      'signature' => signature }
  end
  let(:command) { Struct.new(:trans).new(trans) }
  let(:node_sample) do
    {
      version: 1, coverage: 'node_activity_v1',
      daemon_boot_uuid: SecureRandom.uuid, effect_generation: 4,
      queues: NodeCtld::Queues::QUEUES.to_h do |queue|
        [queue, { workers: 0, reservations: 0 }]
      end,
      pending_reservations: 0, detached_blockers: 0, tracked_children: 0,
      child_coverage: 'unknown', unknown_reasons: ['child_lifetime_unproved'],
      unknown: true, overflow: false
    }
  end
  let(:osctld_sample) do
    {
      'version' => 1, 'coverage' => 'gc_trash_v1',
      'daemon_boot_uuid' => SecureRandom.uuid,
      'pool_instance_uuid' => SecureRandom.uuid, 'generation' => 8,
      'pool' => 'tank', 'state' => 'active',
      'counts' => %w[run_gc trash_prune trash_move].to_h do |name|
        [name, { 'pending' => 0, 'running' => 0 }]
      end,
      'registered_run_datasets' => 0,
      'worker_alive' => { 'run_gc' => true, 'trash_prune' => true },
      'unknown_reasons' => [], 'unknown' => false, 'overflow' => false, 'idle' => true
    }
  end

  before do
    sql_update('storage_freeze_controls', { mode: 1, epoch: 7 }, 'id = 1')
    allow(NodeCtld::Db).to receive(:open).and_yield(shared_db)
  end

  it 'registers 5291 through the normal command loader' do
    require 'nodectld'

    expect(NodeCtld::Command.class_variable_get(:@@handlers).fetch(5291))
      .to eq('NodeCtld::Commands::Storage::ActivityProbe')
  end

  it 'binds a real signature, catalog, freeze and two local samples without quiet authority' do
    activity = instance_double(NodeCtld::Daemon)
    reader = instance_double(described_class::OsctldReader)
    allow(activity).to receive(:node_activity_snapshot).twice.and_return(node_sample)
    allow(reader).to receive(:read!).and_return(osctld_sample)

    result = described_class.run!(command, params, activity:, reader:)

    expect(result).to include(
      protocol_version: 1, request_digest: Digest::SHA256.hexdigest(trans.fetch('input')),
      nonce: params.fetch(:nonce), node_id:, freeze_epoch: 7,
      node_activity_observed: true, node_queues_empty: true,
      gc_trash_observed: true, node_quiet: false, repair_ready: false
    )
    expect(result.fetch(:osctld).keys).to eq(['tank'])
    expect(result).to include(pool_ids: [pool.fetch('id').to_i], zpools: ['tank'])
    expect(result).not_to have_key(:claims)
    expect(JSON.generate(result)).not_to include(pool.fetch('filesystem'))
    expect(activity).to have_received(:node_activity_snapshot)
      .with(hash_including(excluding_transaction_id: 567)).twice
    expect(reader).to have_received(:read!).once
  end

  it 'normalizes an integral decimal GUID from the real Pool row' do
    sql_update('pools', { zpool_guid: 50_001 }, 'id = ?', pool.fetch('id'))
    expect(described_class::Request.decimal(BigDecimal('50001'))).to eq('50001')
    expect do
      described_class::Request.decimal(BigDecimal('50001.5'))
    end.to raise_error(described_class::Invalid, 'invalid Pool GUID')

    request = params.merge(claims: claims.map { |claim| claim.merge('zpool_guid' => '50001') })
    input, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: 123, depends_on_id: nil, handle: 5291, node_id:, reversible: 0,
      input: request
    )
    trans['input'] = input
    trans['signature'] = signature
    activity = instance_double(NodeCtld::Daemon, node_activity_snapshot: node_sample)
    reader = instance_double(described_class::OsctldReader, read!: osctld_sample)

    result = described_class.run!(command, request, activity:, reader:)

    expect(result.fetch(:pool_ids)).to eq([pool.fetch('id').to_i])
    expect(result.fetch(:request_digest)).to eq(Digest::SHA256.hexdigest(input))
  end

  it 'rejects an altered signature or a mismatched signed node before DB access' do
    allow(NodeCtld::Db).to receive(:open).and_raise('DB should not be read')
    trans['signature'] = 'invalid'
    expect { described_class.run!(command, params) }
      .to raise_error(described_class::Invalid, 'activity probe signature is invalid')

    trans['signature'] = NodeCtldSpec::SigningHelpers.sign_base64(trans.fetch('input'))
    wrong = params.merge(node_id: node_id + 1)
    expect { described_class.run!(command, wrong) }
      .to raise_error(described_class::Invalid, 'activity input differs from signed request')
  end

  it 'rejects stale freeze, duplicate claims and a missing Pool claim' do
    activity = instance_double(NodeCtld::Daemon)
    reader = instance_double(described_class::OsctldReader)
    allow(activity).to receive(:node_activity_snapshot).and_return(node_sample)
    allow(reader).to receive(:read!).and_return(osctld_sample)

    sql_update('storage_freeze_controls', { epoch: 8 }, 'id = 1')
    expect { described_class.run!(command, params, activity:, reader:) }
      .to raise_error(described_class::Invalid, /freeze epoch changed/)
    sql_update('storage_freeze_controls', { epoch: 7 }, 'id = 1')

    duplicate = params.merge(claims: claims * 2)
    duplicate_input, duplicate_signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: 123, depends_on_id: nil, handle: 5291, node_id:, reversible: 0,
      input: duplicate
    )
    trans['input'] = duplicate_input
    trans['signature'] = duplicate_signature
    expect { described_class.run!(command, duplicate, activity:, reader:) }
      .to raise_error(described_class::Invalid, /duplicate or unordered/)

    missing = params.merge(claims: [])
    missing_input, missing_signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: 123, depends_on_id: nil, handle: 5291, node_id:, reversible: 0,
      input: missing
    )
    trans['input'] = missing_input
    trans['signature'] = missing_signature
    expect { described_class.run!(command, missing, activity:, reader:) }
      .to raise_error(described_class::Invalid, /invalid activity Pool claims/)
  end

  it 'rejects a catalog added Pool and an epoch change during osctld reading' do
    activity = instance_double(NodeCtld::Daemon)
    allow(activity).to receive(:node_activity_snapshot).and_return(node_sample)
    reader = instance_double(described_class::OsctldReader)
    allow(reader).to receive(:read!) do
      sql_update('storage_freeze_controls', { epoch: 8 }, 'id = 1')
      osctld_sample
    end
    expect { described_class.run!(command, params, activity:, reader:) }
      .to raise_error(described_class::Invalid, /freeze epoch changed/)

    sql_update('storage_freeze_controls', { epoch: 7 }, 'id = 1')
    allow(reader).to receive(:read!).and_return(osctld_sample)
    insert_pool!(filesystem: "tank/other-#{SecureRandom.hex(3)}")
    expect { described_class.run!(command, params, activity:, reader:) }
      .to raise_error(described_class::Invalid, /Pool scope differs/)
  end

  it 'deduplicates two managed roots on one zpool without dropping either claim' do
    second = insert_pool!(filesystem: "tank/second-#{SecureRandom.hex(3)}")
    both = (claims + [{ 'pool_id' => second.fetch('id').to_i,
                        'managed_root' => second.fetch('filesystem'),
                        'zpool' => 'tank', 'zpool_guid' => nil }]).sort_by { |c| c.fetch('pool_id') }
    request = params.merge(claims: both)
    input, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: 123, depends_on_id: nil, handle: 5291, node_id:, reversible: 0,
      input: request
    )
    trans['input'] = input
    trans['signature'] = signature
    activity = instance_double(NodeCtld::Daemon, node_activity_snapshot: node_sample)
    reader = instance_double(described_class::OsctldReader, read!: osctld_sample)

    result = described_class.run!(command, request, activity:, reader:)

    expect(result.fetch(:pool_ids)).to eq(both.map { |claim| claim.fetch('pool_id') })
    expect(result.fetch(:zpools)).to eq(['tank'])
    expect(reader).to have_received(:read!).once
  end

  it 'bounds osctld lines and rejects old, truncated and contradictory replies' do
    Dir.mktmpdir('g1-activity-socket') do |dir|
      path = File.join(dir, 'osctld.sock')
      server = UNIXServer.new(path)
      reader = described_class::OsctldReader.new(socket_path: path)
      deadline = Time.now.utc + 2
      worker = Thread.new do
        client = server.accept
        client.write("#{JSON.generate(version: '1')}\n")
        client.gets
        client.write("#{JSON.generate(status: true, response: osctld_sample)}\n")
        client.close
      end
      expect(reader.read!('tank', deadline:)).to eq(osctld_sample)
      worker.join(2)
      server.close
    end

    [osctld_sample.merge('version' => 0),
     osctld_sample.merge('idle' => true, 'unknown' => true)].each do |bad|
      expect { described_class::OsctldReader.new.send(:validate_response!, bad, 'tank') }
        .to raise_error(described_class::Invalid)
    end

    ['{"status":true', 'x' * 4097].each do |payload|
      Dir.mktmpdir('g1-activity-socket') do |dir|
        path = File.join(dir, 'osctld.sock')
        server = UNIXServer.new(path)
        worker = Thread.new do
          client = server.accept
          client.write("#{JSON.generate(version: '1')}\n")
          client.gets
          client.write(payload)
          client.close
        end

        reader = described_class::OsctldReader.new(socket_path: path)
        expect { reader.read!('tank', deadline: Time.now.utc + 1) }
          .to raise_error(described_class::Invalid, /incomplete|byte limit/)
        worker.join(1)
        server.close
      end
    end
  end

  it 'bounds a silent osctld response by the signed deadline' do
    Dir.mktmpdir('g1-activity-socket') do |dir|
      path = File.join(dir, 'osctld.sock')
      server = UNIXServer.new(path)
      worker = Thread.new do
        client = server.accept
        client.write("#{JSON.generate(version: '1')}\n")
        client.gets
        sleep 0.1
        client.close
      end

      reader = described_class::OsctldReader.new(socket_path: path)
      expect { reader.read!('tank', deadline: Time.now.utc + 0.03) }
        .to raise_error(described_class::Invalid, /timed out/)
      worker.join(1)
      server.close
    end
  end
end
