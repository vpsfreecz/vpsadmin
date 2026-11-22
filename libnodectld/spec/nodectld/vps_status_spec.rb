# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

unless NodeCtld::RpcClient.const_defined?(:Error)
  NodeCtld::RpcClient.const_set(:Error, Class.new(StandardError))
end

require 'nodectld/ct_top'
require 'nodectld/osctl_container'
require 'nodectld/vps_status'

class VpsStatusSpecStatus < NodeCtld::VpsStatus
  attr_accessor :fetched_vpses, :containers, :ct_list_error
  attr_reader :logs

  def initialize
    super
    @logs = []
  end

  def log(*args)
    @logs << args
  end

  protected

  def fetch_vpses
    fetched_vpses
  end

  def ct_list
    raise ct_list_error if ct_list_error

    containers
  end
end

RSpec.describe NodeCtld::VpsStatus do
  subject(:status) do
    VpsStatusSpecStatus.new.tap do |instance|
      instance.fetched_vpses = [vps_row]
      instance.containers = []
    end
  end

  let(:vps_row) do
    {
      'id' => 101,
      'read_hostname' => false,
      'pool_fs' => 'tank/private',
      'autostart_enable' => true
    }
  end

  before do
    stub_node_bunny
    allow(NodeCtld::NodeBunny).to receive(:publish_wait)
  end

  it 'refreshes the auto-start snapshot with the VPS status inventory' do
    status.safe_update
    snapshot = status.vps_autostart_status.snapshot

    expect(snapshot.success).to be(true)
    expect(snapshot.expected).to eq('tank' => 1)
    expect(snapshot.unsatisfied.first.vps_id).to eq('101')
    expect(snapshot.unsatisfied.first.reason).to eq('missing')
  end

  it 'continues status processing but invalidates monitoring for an old API response' do
    status.fetched_vpses = [vps_row.except('autostart_enable')]

    expect { status.safe_update }.not_to raise_error
    expect(status.vps_autostart_status.snapshot.success).to be(false)
    expect(status.logs).to include(
      [:warn, :vps_autostart_status, a_string_matching(/autostart_enable/)]
    )
  end

  it 'invalidates monitoring when the osctld container list fails' do
    status.safe_update

    status.ct_list_error = NodeCtld::SystemCommandFailed.new(
      'osctl ct ls',
      1,
      'failed'
    )

    expect { status.safe_update }.not_to raise_error
    expect(status.vps_autostart_status.snapshot.success).to be(false)
  end

  it 'invalidates monitoring before propagating an unexpected input failure' do
    status.safe_update
    status.ct_list_error = RuntimeError.new('unexpected failure')

    expect { status.safe_update }.to raise_error(
      RuntimeError,
      'unexpected failure'
    )
    expect(status.vps_autostart_status.snapshot.success).to be(false)
  end

  context 'with status reports from Top' do
    let(:frame) do
      JSON.parse(File.read(File.expand_path('../fixtures/partial_memory_failure.json', __dir__)), symbolize_names: true)
    end
    let(:monotonic) { 116_000_000_000 }
    let(:reports) { [] }

    def container(id, pool: 'tank', state: 'running', init_pid: id + 100)
      NodeCtld::OsCtlContainer.new(id: id.to_s, pool:, state:, init_pid:, group_path: "ct#{id}/user-owned", autostart: true)
    end

    def stat(pid, ticks)
      "#{pid} (init with ) spaces) S #{(['0'] * 18).join(' ')} #{ticks} 0\n"
    end

    def publish(data = frame, now: monotonic)
      sample = NodeCtld::CtTop::Sample.new(data, rate: 120)
      expect(sample).to be_valid(now_ns: monotonic)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond).and_return(now)
      status.update(sample)
      reports.to_h { |report| [report.fetch('id'), report] }
    end

    def publish_wire(data)
      reader = NodeCtld::CtTop.new
      reader.instance_variable_set(:@rate, 120)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond).and_return(monotonic)
      reports.clear
      reader.send(:read_samples, StringIO.new("#{data.to_json}\n")) { |sample| status.update(sample) }
      reports.to_h { |report| [report.fetch('id'), report] }
    ensure
      reader&.stop
    end

    def unavailable_usage
      { 'status' => false, 'running' => true, 'cpu_usage' => nil, 'used_memory' => nil, 'process_count' => nil }
    end

    before do
      status.fetched_vpses = [vps_row, vps_row.merge('id' => 102)]
      status.containers = [container(101), container(102)]
      allow(NodeCtld::SystemProbes::Uptime).to receive(:new).and_return(instance_double(NodeCtld::SystemProbes::Uptime, uptime: 1_000))
      allow(OsCtl::Lib::LoadAvgReader).to receive(:read_for).and_return({})
      allow(NodeCtld::NodeBunny).to receive(:publish_wait) { |_, payload, **| reports << JSON.parse(payload) }
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with('/proc/201/stat').and_return(stat(201, 12_345))
      allow(File).to receive(:read).with('/proc/202/stat').and_return(stat(202, 23_456))
    end

    it 'keeps the healthy VPS report when its neighbor lacks memory, using only legacy message fields' do
      results = publish
      expect(results.fetch(101)).to include('status' => true, 'running' => true, 'cpu_usage' => 180.0,
                                            'used_memory' => 1_006_632_960, 'process_count' => 81, 'loadavg' => nil,
                                            'uptime' => 1_000 - (12_345 / Etc.sysconf(Etc::SC_CLK_TCK)))
      expect(results.fetch(101).keys).to match_array(%w[id time status running in_rescue_mode uptime loadavg process_count used_memory cpu_usage hostname])
      expect(results.fetch(102)).to include(unavailable_usage)
    end

    it 'quarantines contradictory typed rows after parsing without poisoning the healthy VPS' do
      a, b, host = frame[:containers]
      b = b.merge(memory: 100)
      variants = [b, b.merge(errors: { cpu_usage: 'invalid_window' }), b.merge(errors: { nproc: 'missing_cgroup_value' }),
                  b.merge(errors: { loadavg: 'missing_container_load' }), b.merge(errors: { run: 'run_changed' }),
                  b.merge(errors: { cpu_limit: 'invalid_limit' }), b.merge(errors: 'malformed')]
      variants.each do |row|
        results = publish_wire(frame.merge(containers: [a, row, host]))
        expect(results.fetch(101)).to include('status' => true, 'running' => true, 'cpu_usage' => 180.0)
        expect(results.fetch(102)).to include(unavailable_usage)
      end
    end

    it 'allows honest unknown limit and load errors and ignores unrecognized diagnostics for reporting' do
      a, b, host = frame[:containers]
      b = b.merge(memory: 100, cpu_limit_state: 'unknown', loadavg: nil,
                  errors: { cpu_limit: 'invalid_limit', loadavg: 'missing_container_load', future_metric: 'unavailable' })
      results = publish_wire(frame.merge(containers: [a, b, host]))
      expect(results.fetch(101)).to include('status' => true, 'cpu_usage' => 180.0)
      expect(results.fetch(102)).to include('status' => true, 'running' => true, 'used_memory' => 100, 'cpu_usage' => 20.0)
    end

    it 'retains valid peers when a complete core has no process count for one VPS' do
      a, b, host = frame[:containers]
      b = b.merge(memory: 100, nproc: nil, errors: { nproc: 'missing_cgroup_value' })
      full = frame.merge(containers: [a, b, host], complete: true, invalid_reason: nil,
                         measurement_window_started_monotonic_ns: 100_000_000_000)
      results = publish_wire(full)
      expect(results.fetch(101)).to include('status' => true, 'cpu_usage' => 180.0)
      expect(results.fetch(102)).to include(unavailable_usage)
    end

    it 'does not attach another pool or either of two ambiguous rows to the running VPS' do
      a, b, host = frame[:containers]
      open_frame = frame.merge(inventory_complete: false, state_counts: nil,
                               containers: [a, b.merge(pool: 'other', memory: 100, errors: {}), b.merge(memory: 200, errors: {}), b, host])
      results = publish(open_frame)
      expect(results.fetch(101)).to include('status' => true)
      expect(results.fetch(102)).to include(unavailable_usage)
    end

    it 'rejects a closed duplicate even when the number of distinct keys matches the count' do
      a, b, host = frame[:containers]
      b = b.merge(memory: 100, errors: {})
      duplicate = frame.merge(containers: [a, b, b.dup, host])
      expect(publish_wire(duplicate)).to be_empty
      results = publish_wire(duplicate.merge(inventory_complete: false))
      expect(results.fetch(101)).to include('status' => true)
      expect(results.fetch(102)).to include(unavailable_usage)
    end

    it 'uses inventory, not Top, for missing, duplicate and stopped containers' do
      status.containers = [container(101), container(101), container(102, state: 'stopped'), container(102, pool: 'other')]
      results = publish
      expect(results.keys).to eq([102])
      expect(results.fetch(102)).to include('status' => true, 'running' => false, 'cpu_usage' => nil, 'used_memory' => nil)
      expect(status.vps_autostart_status.snapshot.success).to be(false)
    end

    it 'publishes only definitive lifecycle states while retaining transitional inventory for autostart monitoring' do
      states = { 103 => 'stopped', 104 => 'starting', 105 => 'stopping', 106 => 'unknown', 107 => 'error',
                 108 => 'future-state', 109 => nil, 110 => '' }
      status.fetched_vpses = (101..110).map { |id| vps_row.merge('id' => id) }
      status.containers = [container(101), container(102, init_pid: nil), *states.map { |id, state| container(id, state:) }]
      now = Time.at(1_000)
      allow(Time).to receive(:now).and_return(now)

      results = publish_wire(frame)
      expect(reports.map { |report| report.fetch('id') }).to contain_exactly(101, 102, 103)
      expect(results.fetch(101)).to include('status' => true, 'running' => true, 'cpu_usage' => 180.0)
      expect(results.fetch(102)).to include(unavailable_usage)
      expect(results.fetch(103)).to include('status' => true, 'running' => false, 'time' => 1_000)
      snapshot = status.vps_autostart_status.snapshot
      expect(snapshot.success).to be(true)
      expect(snapshot.unsatisfied.to_h { |entry| [entry.vps_id.to_i, entry.reason] }).to eq(states.transform_values(&:to_s))

      status.containers[3] = container(104, state: 'stopped')
      allow(Time).to receive(:now).and_return(now + 1)
      results = publish_wire(frame)
      expect(reports.map { |report| report.fetch('id') }).to contain_exactly(101, 102, 103, 104)
      expect(results.fetch(104)).to include('status' => true, 'running' => false, 'time' => 1_001)
    end

    it 'does not assume another pool with the expected ID is the VPS if the correct CT vanished' do
      status.containers = [container(101, pool: 'other'), container(102)]
      expect(publish.keys).to eq([102])
    end

    it 'rejects a recycled PID and retains the peer that still matches' do
      a, b, host = frame[:containers]
      allow(File).to receive(:read).with('/proc/202/stat').and_return(stat(202, 23_457))
      results = publish(frame.merge(containers: [a, b.merge(memory: 100, errors: {}), host]))
      expect(results.fetch(101)).to include('status' => true)
      expect(results.fetch(102)).to include(unavailable_usage)
    end

    it 'rejects transition between the uptime and usage identity checks' do
      allow(File).to receive(:read).with('/proc/201/stat').and_return(stat(201, 12_345), stat(201, 12_346))
      expect(publish.fetch(101)).to include(unavailable_usage)
    end

    it 'does not relabel expired statistics as fresh when status processing takes too long' do
      results = publish(now: 236_000_000_000)
      expect(results.keys).to contain_exactly(101, 102)
      expect(results.values).to all(include(unavailable_usage))
    end

    it 'rejects an unusable CPU window for only that VPS' do
      a, b, host = frame[:containers]
      results = publish(frame.merge(containers: [a.merge(cpu_baseline_sequence: 4), b.merge(memory: 100, errors: {}), host]))
      expect(results.fetch(101)).to include(unavailable_usage)
      expect(results.fetch(102)).to include('status' => true)
    end

    it 'reports genuine zero when limit measurements are explicitly unknown' do
      a, b, host = frame[:containers]
      row = a.merge(cpu_usage: 0.0, memory: 0, nproc: 0, cpu_limit: nil, cpu_limit_state: 'unknown', memory_limit: nil, memory_limit_state: 'unknown')
      expect(publish(frame.merge(containers: [row, b, host])).fetch(101)).to include(
        'status' => true, 'used_memory' => 0, 'cpu_usage' => 0.0, 'process_count' => 0
      )
    end

    it 'marks usage unavailable when uptime cannot be read, without inventing a stop' do
      allow(File).to receive(:read).with('/proc/201/stat').and_raise(Errno::ENOENT)
      expect(publish.fetch(101)).to include(unavailable_usage)
    end

    it 'quarantines missing nullable proof keys instead of treating omission as a known null' do
      a, b, host = frame[:containers]
      b = b.merge(memory: 100, errors: {})
      [b.except(:cpu_limit), b.except(:cpu_limit_state), b.except(:loadavg), b.merge(cpu_limit_state: 'limited')].each do |row|
        results = publish_wire(frame.merge(containers: [a, row, host]))
        expect(results.fetch(101)).to include('status' => true)
        expect(results.fetch(102)).to include(unavailable_usage)
      end
    end

    it 'does not use rejected old or wrapped input as a lifecycle refresh' do
      expect(publish_wire(frame.except(:top_schema))).to be_empty
      expect(publish_wire(frame.merge(top_schema: 1, observation: frame))).to be_empty
    end
  end
end
