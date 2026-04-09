# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/network_interface/remove_veth_routed'
require 'nodectld/net_accounting'

RSpec.describe NodeCtld::Commands::NetworkInterface::RemoveVethRouted do
  let(:driver) { build_vps_driver }
  let(:network_interfaces) do
    Struct.new(:items) do
      def <<(_netif); end

      def remove(_name); end
    end.new([])
  end
  let(:cfg) { Struct.new(:network_interfaces).new(network_interfaces) }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank',
      'vps_id' => 101,
      'user_id' => 55,
      'netif_id' => 77,
      'name' => 'eth1',
      'mac_address' => '02:00:00:00:00:01',
      'max_tx' => 1000,
      'max_rx' => 2000,
      'enable' => false
    )
  end

  before do
    stub_const('NodeCtld::VpsConfig', Module.new)
    stub_const(
      'NodeCtld::VpsConfig::NetworkInterface',
      Class.new do
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end
    )

    allow(network_interfaces).to receive(:<<)
    allow(network_interfaces).to receive(:remove)
    allow(NodeCtld::VpsConfig).to receive(:edit).with('tank', 101).and_yield(cfg)
    allow(NodeCtld::NetAccounting).to receive(:add_netif)
    allow(NodeCtld::NetAccounting).to receive(:remove_netif)
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
  end

  it 'removes the runtime netif, config entry, and accounting state on exec' do
    expect(cmd.exec).to eq(ret: :ok)

    expect(network_interfaces).to have_received(:remove).with('eth1')
    expect(NodeCtld::NetAccounting).to have_received(:remove_netif).with(101, 77)
    expect(cmd).to have_received(:osctl).with(%i[ct netif del], [101, 'eth1'])
  end

  it 'recreates the original runtime netif and config entry on rollback' do
    expect(cmd.rollback).to eq(ret: :ok)

    expect(network_interfaces).to have_received(:<<) do |netif|
      expect(netif.class.name).to eq('NodeCtld::VpsConfig::NetworkInterface')
      expect(netif.name).to eq('eth1')
    end
    expect(cmd).to have_received(:osctl).with(
      %i[ct netif new routed],
      [101, 'eth1'],
      {
        hwaddr: '02:00:00:00:00:01',
        max_tx: 1000,
        max_rx: 2000,
        disable: true
      }
    )
    expect(NodeCtld::NetAccounting).to have_received(:add_netif).with(101, 55, 77, 'eth1')
  end
end
