# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/network_interface/enable'

RSpec.describe NodeCtld::Commands::NetworkInterface::Enable do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'veth_name' => 'eth1'
    )
  end

  before do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
  end

  it 'enables the runtime interface and disables it on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct netif set], [101, 'eth1'], { enable: true })

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct netif set], [101, 'eth1'], { disable: true })
  end
end
