# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::Artifacts do
  let(:format) { VpsAdmin::StorageReconciler::Format }

  def manifest(store, state: 'complete', source_version: format::VERSION)
    source_policy = if source_version == format::VERSION
                      format::LEGACY_POLICY_VERSION
                    else
                      format::POLICY_VERSION
                    end
    data = {
      'version' => source_version,
      'policy_version' => source_policy,
      'state' => state,
      'confidence' => 'advisory_unguarded', 'finding_key' => store.key_metadata,
      'run_id' => store.run_id.to_s, 'mode' => 'bootstrap',
      'scope' => { 'node_id' => '1', 'pool_id' => '2', 'zpool' => 'tank',
                   'managed_root' => 'tank/backup', 'mutation_epoch' => '0' },
      'db' => { 'row_count' => 0, 'digest' => Digest::SHA256.hexdigest(''),
                'confirmation_coverage' => 'selected_chains_only' },
      'zfs' => { 'row_count' => 0, 'digest' => Digest::SHA256.hexdigest('') }
    }
    if source_version == format::MANIFEST_VERSION
      data['record_version'] = format::VERSION
      data['db']['historical_terminal_coverage'] = 'unknown'
      data['db']['evidence_selection'] = {
        'version' => 1, 'strategy' => 'current_graph_and_observable_node_work',
        'node_ids' => ['1'], 'catalog_closure' => 'complete',
        'pending_snapshot_evidence' => 'complete', 'observable_node_work' => 'complete',
        'terminal_history' => 'not_enumerated'
      }
    end
    data['digest'] = format.digest(data)
    data
  end

  def write_complete_capture(store, extra_zfs: [], source_version: format::VERSION)
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
    data = manifest(store, source_version:)
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

  def rewrite_manifest(store)
    data = store.read_json('manifest.json')
    yield data
    data['digest'] = format.digest(data.except('digest'))
    File.write(store.path('manifest.json'), "#{format.canonical(data)}\n")
  end

  it 'keeps the writer on the legacy source pair and record protocol' do
    expect(format::VERSION).to eq(1)
    expect(format::PROTOCOL_VERSION).to eq(1)
    expect(format::MANIFEST_VERSION).to eq(2)
    expect(format::POLICY_VERSION).to eq(2)
    expect(format::PLAN_POLICY_VERSION).to eq(3)

    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      capture = VpsAdmin::StorageReconciler::Capture.new(
        pool_id: SpecSeed.pool.id, mode: 'bootstrap', private_dir: root
      )
      run = Struct.new(:id, :mutation_epoch).new(1, 0)
      capture.instance_variable_set(:@run, run)
      arguments = {
        store:,
        db: { 'pool' => { 'filesystem' => 'tank/backup' }, 'freeze_epoch' => '0' },
        final: { 'row_count' => 0, 'first' => { 'digest' => 'a' * 64 },
                 'second' => { 'digest' => 'a' * 64 },
                 'chunk_chain' => 'b' * 64 },
        run_uuid: SecureRandom.uuid, attempt_uuid: SecureRandom.uuid,
        pool: SpecSeed.pool, state: 'complete'
      }
      data = capture.send(:manifest_for, **arguments)

      expect(data.slice('version', 'policy_version')).to eq(
        'version' => 1, 'policy_version' => 1
      )
      expect(data).not_to have_key('record_version')
      expect(data.fetch('db')).not_to have_key('evidence_selection')
    end
  end

  it 'adapts v1 coverage in memory without changing sealed source bytes' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_complete_capture(store)
      rewrite_manifest(store) do |data|
        data.fetch('db')['historical_terminal_coverage'] = 'complete'
        data.fetch('db')['evidence_selection'] = { 'strategy' => 'claimed_complete' }
      end
      original = File.binread(store.path('manifest.json'))

      artifacts = described_class.new(store)
      report = artifacts.compare!
      coverage = report.fetch('coverage')
      effective = coverage.fetch('effective_coverage')
      expect(artifacts.manifest.fetch('db').fetch('historical_terminal_coverage')).to eq('complete')
      expect(effective.fetch('historical_terminal_coverage')).to eq('unknown')
      expect(effective.fetch('evidence_selection')).to include(
        'version' => 0, 'strategy' => 'legacy_unspecified', 'node_ids' => ['1'],
        'catalog_closure' => 'legacy_unspecified',
        'pending_snapshot_evidence' => 'legacy_unspecified',
        'observable_node_work' => 'legacy_unspecified',
        'terminal_history' => 'legacy_unspecified'
      )
      expect(coverage.slice('source_manifest_version', 'source_policy_version'))
        .to eq('source_manifest_version' => 1, 'source_policy_version' => 1)
      expect(report.fetch('coverage_digest')).to eq(format.digest(coverage))
      expect(report.fetch('policy_version')).to eq(2)
      expect(report.fetch('coverage_warnings')).to contain_exactly(
        'historical_terminal_coverage_unknown', 'legacy_evidence_selection_unproved'
      )
      expect(File.binread(store.path('manifest.json'))).to eq(original)
      expect(artifacts.compare!).to eq(report)
    end
  end

  it 'accepts explicit v2 coverage and publishes separate deterministic policy outputs' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      unknown = format.record('zfs_object', {
        'path' => 'tank/backup/unknown', 'type' => 'filesystem', 'guid' => '7',
        'owner_path' => nil, 'owner_guid' => nil, 'origin' => nil,
        'clones' => [], 'userrefs' => '0', 'deferred_destroy' => 'off',
        'creation' => '1', 'createtxg' => '1'
      })
      write_complete_capture(store, source_version: format::MANIFEST_VERSION,
                                    extra_zfs: [unknown])
      original = File.binread(store.path('manifest.json'))
      store.write('candidate-actions-v2.jsonl') { |file| file.write("old plan v2\n") }
      store.write('dry-run-v2.json') { |file| file.write("old plan v2\n") }

      artifacts = described_class.new(store)
      report = artifacts.compare!
      expect(report.fetch('coverage')).to include(
        'source_manifest_version' => 2, 'source_policy_version' => 2,
        'source_record_version' => 1
      )
      expect(report.dig('coverage', 'effective_coverage', 'evidence_selection'))
        .to eq(store.read_json('manifest.json').dig('db', 'evidence_selection'))
      expect(report.fetch('coverage_digest')).to eq(format.digest(report.fetch('coverage')))
      expect(report.fetch('coverage_warnings')).to eq(['historical_terminal_coverage_unknown'])
      legacy = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 2, create: true)
      write_complete_capture(legacy, extra_zfs: [unknown])
      legacy_report = described_class.new(legacy).compare!
      expect(report.fetch('coverage_digest')).not_to eq(legacy_report.fetch('coverage_digest'))
      advisory = artifacts.dry_run!
      plan = artifacts.plan!
      expect(advisory.fetch('executable_count')).to eq(0)
      expect(plan.fetch('executable_count')).to eq(0)
      expect(artifacts.compare!).to eq(report)
      expect(artifacts.dry_run!).to eq(advisory)
      expect(artifacts.plan!).to eq(plan)
      findings = File.readlines(store.path('findings-v2.jsonl')).map do |line|
        format.parse_line!(line, expected_kind: 'finding').fetch('fields')
      end
      actions = File.readlines(store.path('candidate-actions-v3.jsonl')).map do |line|
        format.parse_line!(line, expected_kind: 'candidate_action').fetch('fields')
      end
      advisory_actions = File.readlines(store.path('advisory-actions-v2.jsonl')).map do |line|
        format.parse_line!(line, expected_kind: 'candidate_action').fetch('fields')
      end
      expect(findings).not_to be_empty
      expect(findings.map { |item| item.fetch('blockers') })
        .to all(include('historical_terminal_coverage_unknown'))
      expect(actions).not_to be_empty
      expect(actions.map { |item| item.fetch('proof_blockers') })
        .to all(include('historical_terminal_coverage_unknown'))
      expect(actions.map { |item| item.fetch('executable') }).to all(be(false))
      expect(advisory_actions).not_to be_empty
      expect(advisory_actions.map { |item| item.fetch('executable') }).to all(be(false))
      expect(File.binread(store.path('candidate-actions-v2.jsonl'))).to eq("old plan v2\n")
      expect(File.binread(store.path('dry-run-v2.json'))).to eq("old plan v2\n")
      expect(File.exist?(store.path('findings-v2.jsonl'))).to be(true)
      expect(File.exist?(store.path('report-v2.json'))).to be(true)
      expect(File.exist?(store.path('advisory-actions-v2.jsonl'))).to be(true)
      expect(File.exist?(store.path('advisory-dry-run-v2.json'))).to be(true)
      expect(File.exist?(store.path('candidate-actions-v3.jsonl'))).to be(true)
      expect(File.exist?(store.path('dry-run-v3.json'))).to be(true)
      expect(File.binread(store.path('manifest.json'))).to eq(original)
    end
  end

  it 'rejects crossed source policies and unsupported v2 coverage claims' do
    changes = [
      [1, ->(data) { data['policy_version'] = 2 }],
      [1, ->(data) { data.fetch('db')['confirmation_coverage'] = 'complete' }],
      [2, ->(data) { data['policy_version'] = 1 }],
      [2, ->(data) { data.delete('record_version') }],
      [2, ->(data) { data.fetch('db').delete('evidence_selection') }],
      [2, ->(data) { data.fetch('db')['historical_terminal_coverage'] = 'complete' }],
      [2, ->(data) { data.dig('db', 'evidence_selection')['node_ids'] = %w[1 1] }],
      [2, ->(data) { data.dig('db', 'evidence_selection')['node_ids'] = ['01'] }],
      [2, ->(data) { data.dig('db', 'evidence_selection')['terminal_history'] = 'complete' }]
    ]
    changes.each do |source_version, edit|
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        write_complete_capture(store, source_version:)
        rewrite_manifest(store, &edit)
        expect { described_class.new(store) }.to raise_error(described_class::Invalid)
      end
    end
  end

  it 'rejects v1 without an explicit canonical scope node' do
    [nil, '01', 'not-a-node'].each do |node_id|
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        write_complete_capture(store)
        rewrite_manifest(store) { |data| data.fetch('scope')['node_id'] = node_id }
        expect { described_class.new(store) }.to raise_error(described_class::Invalid)
      end
    end
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
      action = File.readlines(store.path('advisory-actions-v2.jsonl')).map do |line|
        format.parse_line!(line, expected_kind: 'candidate_action').fetch('fields')
      end.find { |fields| fields.fetch('target_id') == opaque }
      disk_finding = File.readlines(store.path('findings-v2.jsonl')).map do |line|
        format.parse_line!(line, expected_kind: 'finding').fetch('fields')
      end.find { |fields| fields.fetch('subject_id') == opaque }
      expect(action.fetch('action_key')).to match(/\A[0-9a-f]{64}\z/)
      expect(action.fetch('target_id')).to eq(opaque)
      expect(action.fetch('finding_key')).to eq(disk_finding.fetch('finding_key'))
      expect(action.fetch('finding_key')).not_to eq(format.digest(unknown_path))
      expect(format.canonical(summary)).not_to include(unknown_path)
      expect(format.canonical(action)).not_to include(unknown_path)
      expect(action.fetch('operation')).to be_nil
      expect(action.fetch('executable')).to be(false)
    end
  end

  it 'replays an identical comparison after interruption and refuses changed output' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_complete_capture(store)
      artifacts = described_class.new(store)
      interrupted = false
      allow(store).to receive(:write).and_wrap_original do |original, name, &block|
        if name == 'report-v2.json' && !interrupted
          interrupted = true
          raise IOError, 'interrupted before report seal'
        end

        original.call(name, &block)
      end

      expect { artifacts.compare! }.to raise_error(IOError, 'interrupted before report seal')
      finding_bytes = File.binread(store.path('findings-v2.jsonl'))
      expect(File.exist?(store.path('report-v2.json'))).to be(false)
      report = artifacts.compare!
      expect(artifacts.compare!).to eq(report)
      expect(File.binread(store.path('findings-v2.jsonl'))).to eq(finding_bytes)

      File.open(store.path('findings-v2.jsonl'), 'a') { |file| file.write("changed\n") }
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
        if name == 'advisory-dry-run-v2.json' && !interrupted
          interrupted = true
          raise IOError, 'interrupted before dry-run seal'
        end

        original.call(name, &block)
      end

      expect { artifacts.dry_run! }.to raise_error(IOError, 'interrupted before dry-run seal')
      action_bytes = File.binread(store.path('advisory-actions-v2.jsonl'))
      expect(File.exist?(store.path('advisory-dry-run-v2.json'))).to be(false)
      summary = artifacts.dry_run!
      expect(artifacts.dry_run!).to eq(summary)
      expect(File.binread(store.path('advisory-actions-v2.jsonl'))).to eq(action_bytes)

      File.write(store.path('advisory-dry-run-v2.json'), "changed\n")
      expect { artifacts.dry_run! }
        .to raise_error(described_class::Invalid, 'existing report artifact differs from recomputed output')
    end
  end
end
