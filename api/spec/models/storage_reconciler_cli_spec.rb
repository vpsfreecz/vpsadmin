# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler do
  def load_cli(*arguments)
    original_arguments = ARGV.dup
    ARGV.replace(arguments)
    load File.expand_path('../../bin/vpsadmin-storage-reconcile', __dir__)
  ensure
    ARGV.replace(original_arguments)
  end

  %w[compare dry-run plan].each do |command|
    it "returns exit 3 for an unsealed #{command} capture" do
      Dir.mktmpdir do |root|
        VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 91, create: true)

        expect { load_cli(command, '--run-id', '91', '--private-dir', root) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(3) }
      end
    end
  end

  it 'loads offline artifact commands without booting the API or database' do
    Dir.mktmpdir do |root|
      reconciler = described_class
      format = reconciler::Format
      store = reconciler::PrivateStore.new(root:, run_id: 91, create: true)
      db_row = format.record('db_object', {
                               'table' => 'pools', 'id' => '2',
                               'fields' => { 'id' => '2', 'node_id' => '1',
                                             'filesystem' => 'tank/backup', 'role' => '1' }
                             })
      zfs_row = format.record('zfs_object', {
                                'path' => 'tank/backup', 'type' => 'filesystem', 'guid' => '100',
                                'owner_path' => nil, 'owner_guid' => nil, 'origin' => nil,
                                'clones' => [], 'userrefs' => '0', 'deferred_destroy' => 'off',
                                'creation' => '1', 'createtxg' => '1'
                              })
      db_line = "#{format.canonical(db_row)}\n"
      zfs_line = "#{format.canonical(zfs_row)}\n"
      zfs_pass = { 'count' => 1, 'digest' => Digest::SHA256.hexdigest(zfs_line),
                   'zpool_guid' => '900', 'roots' => { 'tank/backup' => '100' } }
      manifest = {
        'version' => format::VERSION,
        'policy_version' => format::LEGACY_POLICY_VERSION,
        'state' => 'complete', 'confidence' => 'advisory_unguarded',
        'finding_key' => store.key_metadata, 'run_id' => '91', 'mode' => 'bootstrap',
        'scope' => { 'node_id' => '1', 'pool_id' => '2', 'zpool' => 'tank',
                     'managed_root' => 'tank/backup', 'mutation_epoch' => '0' },
        'db' => { 'row_count' => 1, 'digest' => Digest::SHA256.hexdigest(db_line),
                  'confirmation_coverage' => 'selected_chains_only',
                  'managed_roots' => ['tank/backup'] },
        'zfs' => zfs_pass.merge('row_count' => 1, 'first' => zfs_pass, 'second' => zfs_pass)
      }
      manifest['digest'] = format.digest(manifest)
      store.write('db.jsonl') { |file| file.write(db_line) }
      store.write('zfs.jsonl') { |file| file.write(zfs_line) }
      store.write('manifest.json') { |file| file.write("#{format.canonical(manifest)}\n") }

      cli = File.expand_path('../../bin/vpsadmin-storage-reconcile', __dir__)
      script = <<~RUBY
        cli = ARGV.shift
        load cli
        abort 'API booted' if defined?(ActiveRecord) || defined?(SysConfig)
      RUBY

      %w[compare dry-run plan].each do |command|
        output, error, status = Open3.capture3(
          { 'RUBYOPT' => nil, 'DATABASE_URL' => nil },
          RbConfig.ruby, '-e', script, cli, command,
          '--run-id', '91', '--private-dir', root
        )
        expect(status.exitstatus).to eq(0), "#{command}: #{error}"
        expect(output).to include("#{command}=complete")
        expect(error).to be_empty
      end
    end
  end

  it 'keeps a capture failure on exit 2' do
    Dir.mktmpdir do |root|
      runner = instance_double(VpsAdmin::StorageReconciler::Capture)
      allow(VpsAdmin::StorageReconciler::Capture).to receive(:new).and_return(runner)
      allow(runner).to receive(:run!).and_raise(VpsAdmin::StorageReconciler::Capture::Incomplete)

      expect { load_cli('capture', '--pool-id', '1', '--mode', 'bootstrap', '--private-dir', root) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
    end
  end

  it 'unlocks a fresh capture signer and reuses the key for another capture' do
    capture = VpsAdmin::StorageReconciler::Capture.new(
      pool_id: 1, mode: 'steady', private_dir: '/tmp'
    )
    allow(VpsAdmin::API::TransactionSigner).to receive(:unlocked?).and_return(false, true)
    allow(capture).to receive(:unlock_signer!)
    allow(capture).to receive(:broker_config!)
      .and_raise(VpsAdmin::StorageReconciler::Capture::Incomplete, 'stop after signer check')

    2.times do
      expect { capture.run! }.to raise_error(
        VpsAdmin::StorageReconciler::Capture::Incomplete, 'stop after signer check'
      )
    end
    expect(capture).to have_received(:unlock_signer!).once
  end

  it 'routes plan through private artifacts without starting capture' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 91, create: true)
      artifacts = instance_double(VpsAdmin::StorageReconciler::Artifacts)
      allow(VpsAdmin::StorageReconciler::PrivateStore).to receive(:new)
        .with(root:, run_id: 91).and_return(store)
      allow(VpsAdmin::StorageReconciler::Artifacts).to receive(:new)
        .with(store).and_return(artifacts)
      allow(artifacts).to receive(:plan!).and_return('action_count' => 3)
      allow(VpsAdmin::StorageReconciler::Capture).to receive(:new)

      expect { load_cli('plan', '--run-id', '91', '--private-dir', root) }
        .to output("run_id=91 plan=complete count=3\n").to_stdout
      expect(VpsAdmin::StorageReconciler::PrivateStore).to have_received(:new)
        .with(root:, run_id: 91)
      expect(VpsAdmin::StorageReconciler::Artifacts).to have_received(:new).with(store)
      expect(artifacts).to have_received(:plan!)
      expect(VpsAdmin::StorageReconciler::Capture).not_to have_received(:new)
    end
  end

  it 'does not mistake a runtime argument error for invalid CLI arguments' do
    Dir.mktmpdir do |root|
      runner = instance_double(VpsAdmin::StorageReconciler::Capture)
      allow(VpsAdmin::StorageReconciler::Capture).to receive(:new).and_return(runner)
      allow(runner).to receive(:run!).and_raise(ArgumentError, 'invalid node result')

      expect { load_cli('capture', '--pool-id', '1', '--mode', 'steady', '--private-dir', root) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
    end
  end
end
