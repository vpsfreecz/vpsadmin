# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/network_interface/route_del'
require 'nodectld/network_interface'

RSpec.describe NodeCtld::Commands::NetworkInterface::RouteDel do
  let(:driver) { build_vps_driver }
  let(:netif) { instance_spy(NodeCtld::NetworkInterface) }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank',
      'vps_id' => 101,
      'veth_name' => 'eth1',
      'addr' => '192.0.2.50',
      'prefix' => 24,
      'version' => 4,
      'unregister' => true,
      'via' => '192.0.2.1',
      'timeout' => 15
    )
  end

  before do
    allow(NodeCtld::NetworkInterface).to receive(:new).with('tank', 101, 'eth1').and_return(netif)
    allow(netif).to receive(:add_route)
    allow(netif).to receive(:del_route)
    allow(cmd).to receive(:wait_for_route_to_clear)
  end

  it 'removes the route on exec' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(netif).to have_received(:del_route).with('192.0.2.50', 24, 4, true)
  end

  it 'waits for conflicts to clear before restoring the route on rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:wait_for_route_to_clear).with(
      4,
      '192.0.2.50',
      24,
      timeout: 15
    )
    expect(netif).to have_received(:add_route).with(
      '192.0.2.50',
      24,
      4,
      true,
      via: '192.0.2.1'
    )
  end
end
