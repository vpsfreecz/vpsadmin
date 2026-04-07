# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/resources'

RSpec.describe NodeCtld::Commands::Vps::Resources do
  let(:driver) { build_vps_driver }

  it 'applies memory, swap, cgroup soft limits, and the lowest positive CPU limit' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'resources' => [
        { 'resource' => 'cpu', 'value' => 4, 'original' => 2 },
        { 'resource' => 'cpu_limit', 'value' => 350, 'original' => 250 },
        { 'resource' => 'memory', 'value' => 2048, 'original' => 1024 },
        { 'resource' => 'swap', 'value' => 512, 'original' => 256 }
      ]
    )
    soft_limit = (2048 * 0.8 * 1024 * 1024).round

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct set memory-limit], [101, '2048M', '512M'])
    expect(cmd).to have_received(:osctl).with(
      %i[ct cgparams set],
      [101, 'memory.soft_limit_in_bytes', soft_limit],
      { version: '1' }
    )
    expect(cmd).to have_received(:osctl).with(
      %i[ct cgparams set],
      [101, 'memory.low', soft_limit],
      { version: '2' }
    )
    expect(cmd).to have_received(:osctl).with(%i[ct set cpu-limit], [101, '350'])
  end

  it 'restores original values and unsets CPU limit when the computed limit is zero' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'resources' => [
        { 'resource' => 'cpu', 'value' => 4, 'original' => 0 },
        { 'resource' => 'memory', 'value' => 2048, 'original' => 1024 },
        { 'resource' => 'swap', 'value' => 512, 'original' => 0 }
      ]
    )
    soft_limit = (1024 * 0.8 * 1024 * 1024).round

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct set memory-limit], [101, '1024M'])
    expect(cmd).to have_received(:osctl).with(
      %i[ct cgparams set],
      [101, 'memory.soft_limit_in_bytes', soft_limit],
      { version: '1' }
    )
    expect(cmd).to have_received(:osctl).with(
      %i[ct cgparams set],
      [101, 'memory.low', soft_limit],
      { version: '2' }
    )
    expect(cmd).to have_received(:osctl).with(%i[ct unset cpu-limit], 101)
  end
end
