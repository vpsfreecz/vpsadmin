# frozen_string_literal: true

require 'spec_helper'

unless NodeCtld::RpcClient.const_defined?(:Error)
  NodeCtld::RpcClient.const_set(:Error, Class.new(StandardError))
end

require 'nodectld/vps_status'
require 'nodectld/osctl_container'

class VpsStatusSpecStatus < NodeCtld::VpsStatus
  attr_accessor :fetched_vpses, :containers, :ct_list_error
  attr_reader :logs, :usage_calls, :uptime_calls, :hostname_calls

  def initialize
    super
    @logs = []
    @usage_calls = []
    @uptime_calls = []
    @hostname_calls = []
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

  def apply_usage_stats(vps)
    @usage_calls << vps.id
    super
  end

  def read_uptime(init_pid)
    @uptime_calls << init_pid
    120
  end

  def osctl_parse(*args)
    @hostname_calls << args
    raise 'unexpected hostname lookup'
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

  describe 'published runtime availability' do
    let(:published) { [] }
    let(:container_data) do
      {
        id: '101',
        pool: 'tank',
        state: 'running',
        autostart: true,
        init_pid: 4321,
        dataset: 'tank/ct/101',
        boot_dataset: 'tank/ct/101',
        boot_rootfs: '/tank/ct/101/private'
      }
    end
    let(:usage) { { id: '101', cpu_usage: 3.5, memory: 4096, nproc: 4 } }

    before do
      allow(NodeCtld::NodeBunny).to receive(:publish_wait) do |_exchange, payload, **_opts|
        published << JSON.parse(payload)
      end
      allow(OsCtl::Lib::LoadAvgReader).to receive(:read_for).and_return({})
      uptime = instance_double(NodeCtld::SystemProbes::Uptime, uptime: 1000)
      allow(NodeCtld::SystemProbes::Uptime).to receive(:new).and_return(uptime)
    end

    [
      ['error with a live-looking init and unknown boot root', { state: 'error', runstate_error: 'saved runtime is missing' }],
      ['old error response without a diagnostic', { state: 'error' }],
      ['error with a null diagnostic', { state: 'error', runstate_error: nil }],
      ['running state with a runtime diagnostic', { runstate_error: 'saved root does not match' }],
      ['running state with an empty non-null diagnostic', { runstate_error: '' }],
      ['running state with a false non-null diagnostic', { runstate_error: false }]
    ].each do |description, attrs|
      it "publishes unavailable status for #{description} without root or usage work" do
        ct = NodeCtld::OsCtlContainer.new(container_data.merge(attrs).merge(boot_dataset: nil, boot_rootfs: nil))
        status.containers = [ct]
        status.fetched_vpses = [vps_row.merge('read_hostname' => true)]

        allow(ct).to receive(:in_ct_boot?).and_call_original

        status.update([usage])

        expect(status.usage_calls).to be_empty
        expect(status.uptime_calls).to be_empty
        expect(status.hostname_calls).to be_empty
        expect(ct).not_to have_received(:in_ct_boot?)
        expect(published.size).to eq(1)
        expect(published.first).to include(
          'id' => 101,
          'status' => false,
          'running' => false,
          'uptime' => nil,
          'loadavg' => nil,
          'process_count' => nil,
          'used_memory' => nil,
          'cpu_usage' => nil,
          'hostname' => nil
        )
        reason = attrs[:runstate_error].nil? ? 'container is in error state' : attrs[:runstate_error]
        expect(status.logs).to include([:warn, :vps_status, "tank:101: status unavailable: #{reason}"])
      end
    end

    %w[running stopped].each do |state|
      [{}, { runstate_error: nil }].each do |attrs|
        it "preserves healthy #{state} reports with #{attrs.empty? ? 'absent' : 'null'} diagnostics" do
          ct = NodeCtld::OsCtlContainer.new(container_data.merge(attrs).merge(state: state))
          status.containers = [ct]

          allow(ct).to receive(:in_ct_boot?).and_call_original

          status.update([usage])

          expect(published.size).to eq(1)
          expect(published.first).to include('id' => 101, 'status' => true, 'running' => state == 'running')
          if state == 'running'
            expect(status.usage_calls).to eq(['101'])
            expect(status.uptime_calls).to eq([4321])
            expect(published.first).to include('uptime' => 120, 'cpu_usage' => 3.5, 'used_memory' => 4096, 'process_count' => 4)
          else
            expect(status.usage_calls).to be_empty
            expect(status.uptime_calls).to be_empty
            expect(ct).not_to have_received(:in_ct_boot?)
            expect(published.first).to include('uptime' => nil, 'cpu_usage' => nil, 'used_memory' => nil, 'process_count' => nil)
          end
        end
      end
    end

    it 'publishes an unavailable container and an unchanged healthy peer together' do
      uncertain = NodeCtld::OsCtlContainer.new(container_data.merge(state: 'error', init_pid: 6666, boot_dataset: nil, boot_rootfs: nil))
      healthy = NodeCtld::OsCtlContainer.new(
        container_data.merge(
          id: '102', dataset: 'tank/ct/102', boot_dataset: 'tank/ct/102', boot_rootfs: '/tank/ct/102/private'
        )
      )
      status.containers = [uncertain, healthy]
      status.fetched_vpses = [vps_row, vps_row.merge('id' => 102)]
      allow(uncertain).to receive(:in_ct_boot?).and_call_original

      status.update([usage.merge(id: '102')])

      expect(status.usage_calls).to eq(['102'])
      expect(status.uptime_calls).to eq([4321])
      expect(uncertain).not_to have_received(:in_ct_boot?)
      reports = published.to_h { |report| [report.fetch('id'), report] }
      expect(reports.keys).to contain_exactly(101, 102)
      expect(reports.fetch(101)).to include('status' => false, 'running' => false, 'cpu_usage' => nil)
      expect(reports.fetch(102)).to include('status' => true, 'running' => true, 'cpu_usage' => 3.5, 'uptime' => 120)
    end
  end
end
