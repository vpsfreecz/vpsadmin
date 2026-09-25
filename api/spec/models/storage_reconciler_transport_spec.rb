# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::NodeTransport do
  let(:format) { VpsAdmin::StorageReconciler::Format }
  let(:run_uuid) { SecureRandom.uuid }
  let(:attempt_uuid) { SecureRandom.uuid }
  let(:nonce) { 'a' * 64 }

  def transport(store, run: run_uuid, attempt: attempt_uuid)
    described_class.new(
      node_domain: 'node.example.test', run_uuid: run, attempt_uuid: attempt,
      node_id: 1, pool_id: 2, zpool: 'tank', managed_root: 'tank/backup',
      roots: ['tank/backup'], nonce:, store:, config: {}
    )
  end

  def frame(sequence: 0, guid: '10')
    record = format.record('zfs_object', {
      'path' => 'tank/backup', 'type' => 'filesystem', 'guid' => guid,
      'owner_path' => nil, 'owner_guid' => nil,
      'origin' => nil, 'clones' => [], 'userrefs' => '0',
      'deferred_destroy' => 'off', 'creation' => '1', 'createtxg' => '1'
    })
    unsigned = {
      'type' => 'chunk', 'version' => format::VERSION,
      'run_uuid' => run_uuid, 'attempt_uuid' => attempt_uuid,
      'node_id' => '1', 'pool_id' => '2', 'zpool' => 'tank',
      'managed_root' => 'tank/backup', 'roots' => ['tank/backup'],
      'nonce' => nonce, 'sequence' => sequence, 'records' => [record],
      'row_count' => 1, 'records_digest' => format.digest([record]),
      'records_bytes' => format.canonical(record).bytesize + 1
    }
    unsigned.merge('digest' => format.digest(unsigned))
  end

  it 'accepts exact broker redelivery within one live attempt and rejects changed bytes' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      first = transport(store)
      first.send(:open_partial!)
      first.send(:apply_chunk!, frame)
      expect { first.send(:apply_chunk!, frame) }.not_to raise_error
      expect(first.instance_variable_get(:@row_count)).to eq(1)
      expect { first.send(:apply_chunk!, frame(guid: '11')) }
        .to raise_error(described_class::Invalid, 'conflicting inventory replay')
      expect { first.send(:apply_chunk!, frame(sequence: 2)) }
        .to raise_error(described_class::Invalid, 'inventory sequence gap')
      first.close
    end
  end

  it 'refuses a crashed attempt after chunk fsync and starts a new run at sequence zero' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      first = transport(store)
      first.send(:open_partial!)
      first.send(:apply_chunk!, frame)
      first.close
      expect { transport(store).send(:open_partial!) }
        .to raise_error(described_class::Invalid, 'interrupted inventory attempt requires a new run')

      new_store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 2, create: true)
      new_run_uuid = SecureRandom.uuid
      new_attempt_uuid = SecureRandom.uuid
      expect(new_run_uuid).not_to eq(run_uuid)
      expect(new_attempt_uuid).not_to eq(attempt_uuid)
      fresh = transport(new_store, run: new_run_uuid, attempt: new_attempt_uuid)
      fresh.send(:open_partial!)
      fresh.send(:apply_chunk!, frame)
      expect(fresh.instance_variable_get(:@sequence)).to eq(1)
      checkpoint = JSON.parse(File.readlines(File.join(new_store.run_directory,
                                                       'zfs-checkpoint.partial')).first)
      expect(checkpoint).to include('sequence' => 0, 'run_uuid' => new_run_uuid,
                                    'attempt_uuid' => new_attempt_uuid)
      fresh.close
    end
  end

  it 'does not accept an old run sealed before final ACK completion' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      store.write('capture-seal.json') { |file| file.write("{\"state\":\"sealed_pending_ack\"}\n") }
      expect do
        VpsAdmin::StorageReconciler::Artifacts.new(store)
      end.to raise_error(VpsAdmin::StorageReconciler::Artifacts::Invalid,
                         'capture is not sealed complete')

      fresh_store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 2, create: true)
      fresh = transport(fresh_store, run: SecureRandom.uuid, attempt: SecureRandom.uuid)
      expect { fresh.send(:open_partial!) }.not_to raise_error
      fresh.close
    end
  end

  it 'returns incomplete promptly when the signed node transaction fails before final' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      receiver = transport(store)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect do
        receiver.receive_until_final!(deadline: Time.now.utc + 60,
                                      failure_check: -> { true })
      end.to raise_error(described_class::Invalid, 'node inventory transaction failed')
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
      expect(File.exist?(store.path('zfs.jsonl'))).to be(false)
      receiver.close
    end
  end
end
