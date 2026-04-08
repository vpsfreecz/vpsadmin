# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/map_mode'
require 'nodectld/vps'

RSpec.describe NodeCtld::Commands::Vps::MapMode do
  let(:driver) { build_vps_driver }

  it 'stops the VPS, changes the map mode, and restores a previously running VPS' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'new_map_mode' => 'native',
      'original_map_mode' => 'zfs'
    )

    allow(cmd).to receive(:status).and_return(:running, :stopped)
    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct stop], 101)
    expect(cmd).to have_received(:osctl).with(%i[ct set map-mode], [101, 'native'])
    expect(cmd).to have_received(:osctl).with(
      %i[ct start],
      101,
      { wait: NodeCtld::Vps::START_TIMEOUT }
    )
  end

  it 'changes the original map mode on rollback without starting a VPS that was already stopped' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'new_map_mode' => 'native',
      'original_map_mode' => 'zfs'
    )

    allow(cmd).to receive(:status).and_return(:stopped, :stopped)
    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct stop], 101)
    expect(cmd).to have_received(:osctl).with(%i[ct set map-mode], [101, 'zfs'])
    expect(cmd).not_to have_received(:osctl).with(
      %i[ct start],
      101,
      { wait: NodeCtld::Vps::START_TIMEOUT }
    )
  end
end
