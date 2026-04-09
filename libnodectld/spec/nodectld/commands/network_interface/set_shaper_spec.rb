# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/network_interface/set_shaper'

RSpec.describe NodeCtld::Commands::NetworkInterface::SetShaper do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'veth_name' => 'eth1',
      'max_tx' => { 'new' => 1000, 'original' => 500 },
      'max_rx' => { 'new' => 2000, 'original' => 750 }
    )
  end

  before do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
  end

  it 'applies the new shaper values and restores the originals on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct netif set],
      [101, 'eth1'],
      { max_tx: 1000, max_rx: 2000 }
    )

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct netif set],
      [101, 'eth1'],
      { max_tx: 500, max_rx: 750 }
    )
  end
end
