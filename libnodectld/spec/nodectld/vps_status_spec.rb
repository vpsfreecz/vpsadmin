# frozen_string_literal: true

require 'spec_helper'

unless NodeCtld::RpcClient.const_defined?(:Error)
  NodeCtld::RpcClient.const_set(:Error, Class.new(StandardError))
end

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
end
