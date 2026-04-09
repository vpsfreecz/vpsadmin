# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/network_interface/host_ip_del'
require 'nodectld/network_interface'

RSpec.describe NodeCtld::Commands::NetworkInterface::HostIpDel do
  let(:driver) { build_vps_driver }
  let(:netif) { instance_spy(NodeCtld::NetworkInterface) }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank',
      'vps_id' => 101,
      'interface' => 'eth1',
      'addr' => '192.0.2.50',
      'prefix' => 24
    )
  end

  before do
    allow(NodeCtld::NetworkInterface).to receive(:new).with('tank', 101, 'eth1').and_return(netif)
    allow(netif).to receive(:add_host_addr)
    allow(netif).to receive(:del_host_addr)
  end

  it 'removes the host address and restores it on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(netif).to have_received(:del_host_addr).with('192.0.2.50', 24)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(netif).to have_received(:add_host_addr).with('192.0.2.50', 24)
  end
end
