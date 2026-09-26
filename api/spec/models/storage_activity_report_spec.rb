# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::ActivityReport do
  let(:pools) do
    [
      { pool_id: 11, node_id: 4, node_domain: 'node.example.test',
        managed_root: 'tank/first', zpool: 'tank', zpool_guid: nil },
      { pool_id: 12, node_id: 4, node_domain: 'node.example.test',
        managed_root: 'tank/second', zpool: 'tank', zpool_guid: nil }
    ]
  end
  let(:status) do
    { mode: 'read_only', stable_epoch: true, db_drained: true,
      count_capped: [], epoch: 9 }
  end
  let(:boot_uuid) { SecureRandom.uuid }
  let(:pool_uuid) { SecureRandom.uuid }

  def output_for(request, generation: 7, osctld_generation: 13)
    {
      'protocol_version' => 1, 'request_uuid' => request.fetch(:request_uuid),
      'attempt_uuid' => request.fetch(:attempt_uuid),
      'request_digest' => 'a' * 64, 'nonce' => request.fetch(:nonce),
      'response_nonce' => 'b' * 64, 'node_id' => request.fetch(:node_id),
      'freeze_epoch' => request.fetch(:freeze_epoch),
      'observed_mode' => 'read_only',
      'pool_ids' => request.fetch(:claims).map { |claim| claim.fetch('pool_id') },
      'zpools' => request.fetch(:claims).map { |claim| claim.fetch('zpool') }.uniq.sort,
      'node_activity' => {
        'version' => 1, 'coverage' => 'node_activity_v1',
        'daemon_boot_uuid' => boot_uuid, 'effect_generation' => generation,
        'child_coverage' => 'unknown', 'unknown' => true,
        'queues' => described_class::EXPECTED_QUEUES.to_h do |name|
          [name, { 'workers' => 0, 'reservations' => 0 }]
        end,
        'pending_reservations' => 0, 'detached_blockers' => 0,
        'tracked_children' => 0, 'overflow' => false,
        'unknown_reasons' => ['child_lifetime_unproved']
      },
      'osctld' => {
        'tank' => {
          'pool' => 'tank', 'version' => 1, 'coverage' => 'gc_trash_v1',
          'daemon_boot_uuid' => boot_uuid, 'pool_instance_uuid' => pool_uuid,
          'generation' => osctld_generation, 'state' => 'active',
          'registered_run_datasets' => 0,
          'worker_alive' => { 'run_gc' => true, 'trash_prune' => true },
          'unknown_reasons' => [], 'unknown' => false, 'overflow' => false,
          'idle' => true,
          'counts' => %w[run_gc trash_prune trash_move].to_h do |kind|
            [kind, { 'pending' => 0, 'running' => 0 }]
          end
        }
      },
      'node_activity_observed' => true, 'node_queues_empty' => true,
      'gc_trash_observed' => true, 'node_quiet' => false, 'repair_ready' => false
    }
  end

  def run_report(root, probe_runner:, status_reader: -> { status })
    captures = []
    report = described_class.new(
      private_dir: root, status_reader:, catalog_reader: -> { pools },
      probe_runner:, signer_unlocker: -> {},
      capture_runner: lambda do |pool_id, capture_root|
        captures << [pool_id, capture_root]
        pool_id + 100
      end
    )
    [report, report.run!, captures]
  end

  it 'unlocks the signer once for a locked process and reuses its loaded key' do
    runner = described_class.new(private_dir: '/tmp')
    capture = instance_double(VpsAdmin::StorageReconciler::Capture)
    allow(VpsAdmin::API::TransactionSigner).to receive(:unlocked?).and_return(false, true)
    allow(VpsAdmin::StorageReconciler::Capture).to receive(:new).and_return(capture)
    allow(capture).to receive(:unlock_signer!)

    2.times { runner.send(:unlock_signer!, pools.first) }

    expect(VpsAdmin::StorageReconciler::Capture).to have_received(:new).once
    expect(capture).to have_received(:unlock_signer!).once
  end

  it 'brackets both Pool claims with one node/zpool probe per side and private output' do
    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      requests = []
      probe = lambda do |node_id, domain, request|
        expect([node_id, domain]).to eq([4, 'node.example.test'])
        requests << request
        output_for(request)
      end
      runner, result, captures = run_report(root, probe_runner: probe)

      expect(requests.length).to eq(2)
      expect(requests.map { |r| r.fetch(:claims).length }).to eq([2, 2])
      expect(requests.map { |r| r.fetch(:claims).map { |c| c.fetch('zpool') }.uniq })
        .to eq([['tank'], ['tank']])
      expect(captures.map(&:first)).to eq([11, 12])
      expect(result).to include(
        'state' => 'sampled_incomplete', 'reason' => 'child_lifetime_unproved',
        'pool_ids' => [11, 12], 'node_ids' => [4],
        'node_quiet' => false, 'repair_ready' => false, 'executable' => false
      )
      path = File.join(runner.report_directory, 'report.json')
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      expect(JSON.parse(File.read(path))).to eq(result)
      expect(File.read(path)).not_to include('tank/first', 'tank/second')
    end
  end

  it 'accepts a capped historical settled count when DB work is drained' do
    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      settled = status.merge(count_capped: [:settled_unverified_intents])
      probe = ->(_node_id, _domain, request) { output_for(request) }

      _runner, result, captures = run_report(
        root, status_reader: -> { settled }, probe_runner: probe
      )

      expect(captures.length).to eq(2)
      expect(result).to include('state' => 'sampled_incomplete',
                                'reason' => 'child_lifetime_unproved')
    end
  end

  it 'rejects a capped blocking count even if a status reader claims drained' do
    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      calls = 0
      capped = status.merge(count_capped: %i[settled_unverified_intents prepared_intents])
      probe = lambda do |_node_id, _domain, request|
        calls += 1
        output_for(request)
      end

      _runner, result, captures = run_report(
        root, status_reader: -> { capped }, probe_runner: probe
      )

      expect(result).to include('state' => 'unknown',
                                'reason' => 'storage freeze is not DB-drained at a stable epoch')
      expect(calls).to eq(0)
      expect(captures).to be_empty
    end
  end

  it 'marks a changed node or osctld generation unknown even with complete inventory' do
    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      samples = 0
      probe = lambda do |_node_id, _domain, request|
        samples += 1
        output_for(request, generation: samples, osctld_generation: samples)
      end
      _runner, result, = run_report(root, probe_runner: probe)

      expect(result).to include('state' => 'unknown', 'reason' => 'activity_generation_changed')
      expect(result.fetch('observations')).to include('generations_stable' => false)
    end
  end

  it 'rejects stale freeze or an incomplete two-pass capture before the second probes' do
    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      calls = 0
      probe = lambda do |_node_id, _domain, request|
        calls += 1
        output_for(request)
      end
      stale = -> { status.merge(stable_epoch: false) }
      _runner, result, = run_report(root, status_reader: stale, probe_runner: probe)
      expect(result).to include('state' => 'unknown',
                                'reason' => 'storage freeze is not DB-drained at a stable epoch')
      expect(calls).to eq(0)
    end

    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      calls = 0
      probe = lambda do |_node_id, _domain, request|
        calls += 1
        output_for(request)
      end
      runner = described_class.new(
        private_dir: root, status_reader: -> { status },
        catalog_reader: -> { pools }, probe_runner: probe,
        signer_unlocker: -> {},
        capture_runner: ->(_pool_id, _dir) { raise described_class::Incomplete, 'inventory incomplete' }
      )
      expect(runner.run!).to include('state' => 'unknown', 'reason' => 'inventory incomplete')
      expect(calls).to eq(1)
    end
  end

  it 'refuses missing zpool output rather than accepting a truncated scope' do
    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      probe = lambda do |_node_id, _domain, request|
        output_for(request).merge('osctld' => {})
      end
      _runner, result, captures = run_report(root, probe_runner: probe)

      expect(result).to include('state' => 'unknown', 'reason' => 'osctld scope is incomplete')
      expect(captures).to be_empty
    end
  end

  it 'rejects an idle claim with a dead osctld worker' do
    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      probe = lambda do |_node_id, _domain, request|
        output = output_for(request)
        output.fetch('osctld').fetch('tank').fetch('worker_alive')['run_gc'] = false
        output
      end

      _runner, result, captures = run_report(root, probe_runner: probe)

      expect(result).to include('state' => 'unknown',
                                'reason' => 'osctld known state is contradictory')
      expect(captures).to be_empty
    end
  end

  it 'normalizes integral decimal catalog GUIDs without accepting fractional values' do
    report = described_class.new(private_dir: '/tmp')

    expect(report.send(:decimal_guid, BigDecimal('50001'))).to eq('50001')
    expect(report.send(:decimal_guid, BigDecimal('50001.000'))).to eq('50001')
    expect { report.send(:decimal_guid, BigDecimal('50001.5')) }
      .to raise_error(described_class::Incomplete, 'Pool GUID is invalid')
  end

  it 'ends the aggregate evidence interval after four monotonic hours' do
    Dir.mktmpdir('g1-report') do |root|
      File.chmod(0o700, root)
      tick = 0
      probes = 0
      runner = described_class.new(
        private_dir: root, clock: -> { tick },
        status_reader: -> { status }, catalog_reader: -> { pools },
        signer_unlocker: -> {},
        probe_runner: lambda do |_node_id, _domain, request|
          probes += 1
          output_for(request)
        end,
        capture_runner: lambda do |pool_id, _dir|
          tick = described_class::MAX_REPORT_SECONDS + 1
          pool_id + 100
        end
      )

      result = runner.run!

      expect(result).to include('state' => 'unknown',
                                'reason' => 'activity report deadline elapsed',
                                'node_quiet' => false, 'repair_ready' => false)
      expect(probes).to eq(1)
      expect(JSON.parse(File.read(File.join(runner.report_directory, 'report.json')))).to eq(result)
    end
  end
end
