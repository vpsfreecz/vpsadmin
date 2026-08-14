# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/queues'
require 'nodectld/dns_config'
require 'nodectld/dns_server_zone'
require 'nodectld/dns_transfer_probe'

# The scheduler examples intentionally share one complete path fixture.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe NodeCtld::DnsTransferProbe do
  let(:probe) do
    stub_node_bunny
    described_class.new(runner: runner)
  end
  let(:runner) { instance_double(NodeCtld::DnsTransferProbeRunner) }
  let(:configured_zones) { [zone] }
  let(:dns_config) do
    instance_double(NodeCtld::DnsConfig, zones: configured_zones)
  end
  let(:zone) do
    NodeCtld::DnsServerZone.new(
      id: 10,
      name: 'probe.example.test.',
      source: 'external_source',
      type: 'secondary_type',
      enabled: true,
      primaries: [primary],
      secondaries: [],
      primary_transfer_generation: 'generation',
      primary_transfer_tracking_started_at: Time.now.to_i - 60,
      probe_source_addrs: {
        'ipv4' => '192.0.2.10',
        'ipv6' => '2001:db8::10'
      },
      load_db: false
    ).tap { |v| v.loaded_serial = 100 }
  end
  let(:primary) do
    {
      'id' => 20,
      'kind' => 'user_primary',
      'ip_addr' => '192.0.2.20',
      'tsig_key' => nil
    }
  end
  let(:probe_tmpdir) { Dir.mktmpdir('dns-transfer-probe-spec') }

  before do
    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config)
    allow(runner).to receive(:prepare)
    allow(runner).to receive(:release)
    $CFG.patch(
      dns_server: {
        transfer_probe_state_file: File.join(probe_tmpdir, 'state.json')
      }
    )
  end

  after do
    described_class.instance = nil
    FileUtils.rm_rf(probe_tmpdir)
  end

  it 'uses deterministic staggering and bounded failure retry intervals' do
    first_delay = probe.send(:initial_delay, '10:20:generation')
    second_delay = probe.send(:initial_delay, '10:20:generation')
    expect(first_delay).to eq(second_delay)
    expect(first_delay).to be >= 1
    expect(first_delay).to be <= 60
    expect(probe.send(:next_interval, status: 'failed', failure_class: 'network')).to eq(300)
    expect(
      probe.send(
        :next_interval,
        status: 'failed',
        failure_class: 'primary',
        reason_code: 'refused'
      )
    ).to eq(300)
    expect(
      probe.send(
        :next_interval,
        status: 'failed',
        failure_class: 'primary',
        reason_code: 'invalid_zone'
      )
    ).to eq(3600)
    expect(
      probe.send(
        :next_interval,
        status: 'failed',
        failure_class: 'primary',
        reason_code: 'protocol_error'
      )
    ).to eq(3600)
    expect(
      probe.send(
        :next_interval,
        status: 'failed',
        failure_class: 'primary',
        reason_code: 'stale'
      )
    ).to eq(3600)
    expect(probe.send(:next_interval, status: 'success', failure_class: nil)).to eq(3600)

    5.times do |i|
      probe.instance_variable_get(:@running)[i.to_s] = described_class::RunningProbe.new
    end
    expect(probe.send(:available_slots)).to eq(0)
  end

  it 'schedules every configured user primary and ignores vpsAdmin peers' do
    second_primary = primary.merge('id' => 21, 'ip_addr' => '192.0.2.21')
    peer = primary.merge('id' => 30, 'kind' => 'vpsadmin_peer', 'ip_addr' => '192.0.2.30')
    zone.primaries.push(second_primary, peer)
    expect(probe.send(:probe_paths)).to contain_exactly(
      [zone, primary],
      [zone, second_primary]
    )
  end

  it 'keeps an immediate follow-up requested while another probe is running' do
    key = probe.send(:path_key, zone, primary)
    pending_at = Time.now.to_f
    probe.instance_variable_get(:@schedule)[key] = pending_at
    allow(runner).to receive(:run).and_return(
      status: 'success',
      attempt_kind: 'ixfr_probe',
      failure_class: nil
    )
    allow(probe).to receive(:publish)

    probe.send(:run_scheduled_probe, key, zone, primary)

    expect(probe.instance_variable_get(:@schedule)[key]).to eq(pending_at)
  end

  it 'retries failed AXFR validation after a nodectld restart' do
    key = probe.send(:path_key, zone, primary)
    allow(runner).to receive(:run).and_return(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'invalid_zone',
      reason: 'Invalid zone',
      message: 'Invalid zone'
    )
    allow(probe).to receive(:publish)

    probe.send(:run_scheduled_probe, key, zone, primary)

    restarted_probe = described_class.new(runner: runner)
    expect(restarted_probe.send(:needs_axfr?, key)).to be(true)
  end

  it 'keeps full-validation recovery latched across generation rotation' do
    old_key = probe.send(:path_key, zone, primary)
    allow(runner).to receive(:run).and_return(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'invalid_zone',
      reason: 'Invalid zone',
      message: 'Invalid zone'
    )
    allow(probe).to receive(:publish)

    probe.send(:run_scheduled_probe, old_key, zone, primary)
    zone.instance_variable_set(:@primary_transfer_generation, 'next-generation')
    new_key = probe.send(:path_key, zone, primary)

    restarted_probe = described_class.new(runner: runner)
    expect(restarted_probe.send(:needs_axfr?, new_key)).to be(true)
  end

  it 'persists the AXFR requirement before publishing the failure' do
    key = probe.send(:path_key, zone, primary)
    allow(runner).to receive(:run).and_return(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'invalid_zone',
      reason: 'Invalid zone',
      message: 'Invalid zone'
    )
    allow(probe).to receive(:publish).and_raise('broker unavailable')

    probe.send(:run_scheduled_probe, key, zone, primary)

    restarted_probe = described_class.new(runner: runner)
    expect(restarted_probe.send(:needs_axfr?, key)).to be(true)
  end

  it 'schedules newly added paths within sixty seconds' do
    now = Time.now.to_f

    probe.send(:schedule_probes)

    key = probe.send(:path_key, zone, primary)
    scheduled_at = probe.instance_variable_get(:@schedule).fetch(key)
    expect(scheduled_at).to be >= now + 1
    expect(scheduled_at).to be <= now + 60.1
  end

  it 'removes pending paths after a zone is deleted' do
    probe.send(:schedule_probes)
    key = probe.send(:path_key, zone, primary)
    configured_zones.clear

    probe.send(:schedule_probes)

    expect(probe.instance_variable_get(:@schedule)).not_to have_key(key)
  end

  it 'schedules a newly added primary within sixty seconds' do
    probe.send(:schedule_probes)
    second_primary = primary.merge('id' => 21, 'ip_addr' => '192.0.2.21')
    zone.primaries.push(second_primary)
    now = Time.now.to_f

    probe.send(:schedule_probes)

    key = probe.send(:path_key, zone, second_primary)
    scheduled_at = probe.instance_variable_get(:@schedule).fetch(key)
    expect(scheduled_at).to be >= now + 1
    expect(scheduled_at).to be <= now + 60.1
  end

  it 'cancels a running service when its path is removed' do
    key = probe.send(:path_key, zone, primary)
    running = described_class::RunningProbe.new(
      unit_name: 'vpsadmin-dns-transfer-probe-test',
      cancelled: false
    )
    probe.instance_variable_get(:@running)[key] = running
    zone.primaries.clear
    allow(runner).to receive(:cancel)

    probe.send(:schedule_probes)

    expect(running.cancelled).to be(true)
    expect(runner).to have_received(:cancel).with(running.unit_name)
  end

  it 'releases a prepared service when its path is removed before launch' do
    key = probe.send(:path_key, zone, primary)
    running = described_class::RunningProbe.new(
      unit_name: 'vpsadmin-dns-transfer-probe-prelaunch',
      cancelled: true
    )
    probe.instance_variable_get(:@running)[key] = running
    allow(runner).to receive(:run)

    probe.send(:run_scheduled_probe, key, zone, primary, running)

    expect(runner).not_to have_received(:run)
    expect(runner).to have_received(:release).with(running.unit_name)
    expect(probe.instance_variable_get(:@running)).not_to have_key(key)
  end

  it 'releases the slot and retries when a probe thread cannot be created' do
    key = probe.send(:path_key, zone, primary)
    probe.instance_variable_get(:@schedule)[key] = Time.now.to_f - 1
    allow(probe).to receive(:start_probe_thread).and_raise(
      ThreadError,
      'resource temporarily unavailable'
    )

    probe.send(:schedule_probes)

    expect(probe.instance_variable_get(:@running)).not_to have_key(key)
    expect(probe.instance_variable_get(:@schedule).fetch(key)).to be > Time.now.to_f
    expect(runner).to have_received(:release)
  end

  it 'drops a completed result after its path is removed' do
    key = probe.send(:path_key, zone, primary)
    allow(runner).to receive(:run) do
      configured_zones.clear
      {
        status: 'success',
        attempt_kind: 'ixfr_probe',
        message: 'ready'
      }
    end
    allow(probe).to receive(:publish)

    probe.send(:run_scheduled_probe, key, zone, primary)

    expect(probe).not_to have_received(:publish)
  end

  it 'sends no path identity or broker metadata to the worker' do
    job = probe.send(:probe_job, zone, primary, force_axfr: false)

    expect(job).to include(
      'zone_name' => zone.name,
      'primary_addr' => primary.fetch('ip_addr'),
      'source_addr' => '192.0.2.10'
    )
    expect(job.keys).not_to include(
      'dns_server_zone_id',
      'dns_zone_transfer_id',
      'configuration_generation',
      'event_key'
    )
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
