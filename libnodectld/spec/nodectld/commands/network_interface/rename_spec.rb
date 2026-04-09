# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/network_interface/rename'
require 'nodectld/net_accounting'
require 'nodectld/vps'

RSpec.describe NodeCtld::Commands::NetworkInterface::Rename do
  let(:driver) { build_vps_driver }
  let(:network_interfaces) do
    Struct.new do
      def rename(_from, _to); end
    end.new
  end
  let(:cfg) { Struct.new(:network_interfaces).new(network_interfaces) }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank',
      'vps_id' => 101,
      'netif_id' => 77,
      'original' => 'eth1',
      'name' => 'wan0'
    )
  end

  before do
    stub_const('NodeCtld::VpsConfig', Module.new)
    allow(network_interfaces).to receive(:rename)
    allow(NodeCtld::VpsConfig).to receive(:edit).with('tank', 101).and_yield(cfg)
    allow(NodeCtld::NetAccounting).to receive(:rename_netif)
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
  end

  it 'renames the runtime interface and restores the VPS when it was running' do
    allow(cmd).to receive(:status).and_return(:running, :stopped)

    expect(cmd.exec).to eq(ret: :ok)

    expect(cmd).to have_received(:osctl).with(%i[ct stop], 101)
    expect(cmd).to have_received(:osctl).with(%i[ct netif rename], [101, 'eth1', 'wan0'])
    expect(cmd).to have_received(:osctl).with(
      %i[ct start],
      101,
      { wait: NodeCtld::Vps::START_TIMEOUT }
    )
    expect(NodeCtld::NetAccounting).to have_received(:rename_netif).with(101, 77, 'wan0')
    expect(network_interfaces).to have_received(:rename).with('eth1', 'wan0')
  end

  it 'reverts the rename without starting a VPS that stayed stopped' do
    allow(cmd).to receive(:status).and_return(:stopped, :stopped)

    expect(cmd.rollback).to eq(ret: :ok)

    expect(cmd).to have_received(:osctl).with(%i[ct stop], 101)
    expect(cmd).to have_received(:osctl).with(%i[ct netif rename], [101, 'wan0', 'eth1'])
    expect(cmd).not_to have_received(:osctl).with(
      %i[ct start],
      101,
      { wait: NodeCtld::Vps::START_TIMEOUT }
    )
    expect(NodeCtld::NetAccounting).to have_received(:rename_netif).with(101, 77, 'eth1')
    expect(network_interfaces).to have_received(:rename).with('wan0', 'eth1')
  end
end
