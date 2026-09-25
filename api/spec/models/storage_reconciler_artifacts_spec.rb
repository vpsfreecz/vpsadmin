# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::Artifacts do
  let(:format) { VpsAdmin::StorageReconciler::Format }

  def manifest(store, state: 'complete')
    data = {
      'version' => format::VERSION, 'policy_version' => format::POLICY_VERSION,
      'state' => state,
      'confidence' => 'advisory_unguarded', 'finding_key' => store.key_metadata,
      'run_id' => '1', 'mode' => 'bootstrap',
      'scope' => { 'node_id' => '1', 'pool_id' => '2', 'zpool' => 'tank',
                   'managed_root' => 'tank/backup', 'mutation_epoch' => '0' },
      'db' => { 'row_count' => 0, 'digest' => Digest::SHA256.hexdigest(''),
                'confirmation_coverage' => 'selected_chains_only' },
      'zfs' => { 'row_count' => 0, 'digest' => Digest::SHA256.hexdigest('') }
    }
    data['digest'] = format.digest(data)
    data
  end

  def write_complete_capture(store, extra_zfs: [])
    db_row = format.record('db_object', {
      'table' => 'pools', 'id' => '2',
      'fields' => { 'id' => '2', 'node_id' => '1',
                    'filesystem' => 'tank/backup', 'role' => '1' }
    })
    zfs_row = format.record('zfs_object', {
      'path' => 'tank/backup', 'type' => 'filesystem', 'guid' => '100',
      'owner_path' => nil, 'owner_guid' => nil,
      'origin' => nil, 'clones' => [], 'userrefs' => '0',
      'deferred_destroy' => 'off', 'creation' => '1', 'createtxg' => '1'
    })
    db_line = "#{format.canonical(db_row)}\n"
    zfs_line = ([zfs_row] + extra_zfs).map { |row| "#{format.canonical(row)}\n" }.join
    data = manifest(store)
    data['db']['row_count'] = 1
    data['db']['digest'] = Digest::SHA256.hexdigest(db_line)
    data['zfs']['row_count'] = extra_zfs.size + 1
    data['zfs']['digest'] = Digest::SHA256.hexdigest(zfs_line)
    pass = { 'count' => data['zfs']['row_count'], 'digest' => data['zfs']['digest'],
             'zpool_guid' => '900', 'roots' => { 'tank/backup' => '100' } }
    data['zfs']['first'] = pass
    data['zfs']['second'] = pass
    data['db']['managed_roots'] = ['tank/backup']
    data['digest'] = format.digest(data.except('digest'))
    store.write('db.jsonl') { |file| file.write(db_line) }
    store.write('zfs.jsonl') { |file| file.write(zfs_line) }
    store.write('manifest.json') { |file| file.write("#{format.canonical(data)}\n") }
  end

  it 'refuses partial and tampered manifests before opening a capture' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      store.write('manifest.json') do |file|
        file.write("#{format.canonical(manifest(store, state: 'sealed_pending_ack'))}\n")
      end
      expect { described_class.new(store) }
        .to raise_error(described_class::Invalid, 'capture is not sealed complete')
    end
  end

  it 'rejects key loss instead of silently regenerating after a run exists' do
    Dir.mktmpdir do |root|
      VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      File.unlink(File.join(root, 'finding-key.bin'))

      expect do
        VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1)
      end.to raise_error(VpsAdmin::StorageReconciler::PrivateStore::Invalid,
                         'finding key is missing')
    end
  end

  it 'rejects a mismatched key fingerprint and a symlinked key' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      data = manifest(store)
      data['finding_key']['key_id'] = 'f' * 32
      data['digest'] = format.digest(data.except('digest'))
      store.write('manifest.json') { |file| file.write("#{format.canonical(data)}\n") }
      expect { described_class.new(store) }
        .to raise_error(VpsAdmin::StorageReconciler::PrivateStore::Invalid,
                        'finding key metadata mismatch')

      key_path = File.join(root, 'finding-key.bin')
      real_key_path = File.join(root, 'renamed-key.bin')
      File.rename(key_path, real_key_path)
      File.symlink(real_key_path, key_path)
      expect do
        VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1)
      end.to raise_error(VpsAdmin::StorageReconciler::PrivateStore::Invalid,
                         'finding key is a symlink')
    end
  end

  it 'rejects a complete manifest whose DB stream checksum is wrong' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      data = manifest(store)
      data['db']['digest'] = 'a' * 64
      data['digest'] = format.digest(data.except('digest'))
      store.write('manifest.json') { |file| file.write("#{format.canonical(data)}\n") }
      store.write('db.jsonl') { |file| file.write('') }

      expect do
        described_class.new(store).send(:read_records, 'db.jsonl', 'db_object', data.fetch('db'))
      end.to raise_error(described_class::Invalid, 'artifact count or checksum differs from manifest')
    end
  end

  it 'keeps unknown paths out of DB-facing finding and action keys' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      unknown_path = 'tank/backup/member-guessable'
      unknown = format.record('zfs_object', {
        'path' => unknown_path, 'type' => 'filesystem', 'guid' => '7',
        'owner_path' => nil, 'owner_guid' => nil,
        'origin' => nil, 'clones' => [], 'userrefs' => '0',
        'deferred_destroy' => 'off', 'creation' => '1', 'createtxg' => '1'
      })
      write_complete_capture(store, extra_zfs: [unknown])
      opaque = store.opaque_disk_key(
        node_id: 1, zpool: 'tank', path: unknown_path, type: 'filesystem', guid: '7'
      )
      artifacts = described_class.new(store)
      artifacts.compare!
      summary = artifacts.dry_run!
      action = File.readlines(store.path('candidate-actions-v1.jsonl')).map do |line|
        format.parse_line!(line, expected_kind: 'candidate_action').fetch('fields')
      end.find { |fields| fields.fetch('target_id') == opaque }
      disk_finding = File.readlines(store.path('findings-v1.jsonl')).map do |line|
        format.parse_line!(line, expected_kind: 'finding').fetch('fields')
      end.find { |fields| fields.fetch('subject_id') == opaque }
      expect(action.fetch('action_key')).to match(/\A[0-9a-f]{64}\z/)
      expect(action.fetch('target_id')).to eq(opaque)
      expect(action.fetch('finding_key')).to eq(disk_finding.fetch('finding_key'))
      expect(action.fetch('finding_key')).not_to eq(format.digest(unknown_path))
      expect(format.canonical(summary)).not_to include(unknown_path)
      expect(format.canonical(action)).not_to include(unknown_path)
      expect(action.fetch('operation')).to be_nil
    end
  end

  it 'replays an identical comparison after interruption and refuses changed output' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_complete_capture(store)
      artifacts = described_class.new(store)
      interrupted = false
      allow(store).to receive(:write).and_wrap_original do |original, name, &block|
        if name == 'report-v1.json' && !interrupted
          interrupted = true
          raise IOError, 'interrupted before report seal'
        end

        original.call(name, &block)
      end

      expect { artifacts.compare! }.to raise_error(IOError, 'interrupted before report seal')
      finding_bytes = File.binread(store.path('findings-v1.jsonl'))
      expect(File.exist?(store.path('report-v1.json'))).to be(false)
      report = artifacts.compare!
      expect(artifacts.compare!).to eq(report)
      expect(File.binread(store.path('findings-v1.jsonl'))).to eq(finding_bytes)

      File.open(store.path('findings-v1.jsonl'), 'a') { |file| file.write("changed\n") }
      expect { artifacts.compare! }
        .to raise_error(described_class::Invalid, 'existing report artifact differs from recomputed output')
    end
  end

  it 'replays an identical dry run after interruption and refuses changed output' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_complete_capture(store)
      artifacts = described_class.new(store)
      artifacts.compare!
      interrupted = false
      allow(store).to receive(:write).and_wrap_original do |original, name, &block|
        if name == 'dry-run-v1.json' && !interrupted
          interrupted = true
          raise IOError, 'interrupted before dry-run seal'
        end

        original.call(name, &block)
      end

      expect { artifacts.dry_run! }.to raise_error(IOError, 'interrupted before dry-run seal')
      action_bytes = File.binread(store.path('candidate-actions-v1.jsonl'))
      expect(File.exist?(store.path('dry-run-v1.json'))).to be(false)
      summary = artifacts.dry_run!
      expect(artifacts.dry_run!).to eq(summary)
      expect(File.binread(store.path('candidate-actions-v1.jsonl'))).to eq(action_bytes)

      File.write(store.path('dry-run-v1.json'), "changed\n")
      expect { artifacts.dry_run! }
        .to raise_error(described_class::Invalid, 'existing report artifact differs from recomputed output')
    end
  end
end
