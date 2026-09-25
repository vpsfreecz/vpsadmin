# frozen_string_literal: true

require 'spec_helper'
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

  it 'keeps a capture failure on exit 2' do
    Dir.mktmpdir do |root|
      runner = instance_double(VpsAdmin::StorageReconciler::Capture)
      allow(VpsAdmin::StorageReconciler::Capture).to receive(:new).and_return(runner)
      allow(runner).to receive(:run!).and_raise(VpsAdmin::StorageReconciler::Capture::Incomplete)

      expect { load_cli('capture', '--pool-id', '1', '--mode', 'bootstrap', '--private-dir', root) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
    end
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
