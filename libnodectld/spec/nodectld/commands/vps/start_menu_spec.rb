# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/start_menu'

RSpec.describe NodeCtld::Commands::Vps::StartMenu do
  let(:driver) { build_vps_driver }

  it 'sets the requested timeout on exec' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'new_timeout' => 30,
      'original_timeout' => 0
    )

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set start-menu],
      101,
      { timeout: 30 }
    )
  end

  it 'unsets the start menu when the new timeout is zero' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'new_timeout' => 0,
      'original_timeout' => 15
    )

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct unset start-menu], 101)
  end

  it 'restores the original timeout on rollback' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'new_timeout' => 0,
      'original_timeout' => 15
    )

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set start-menu],
      101,
      { timeout: 15 }
    )
  end
end
