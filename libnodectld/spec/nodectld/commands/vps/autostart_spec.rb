# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/autostart'

RSpec.describe NodeCtld::Commands::Vps::Autostart do
  let(:driver) { build_vps_driver }

  it 'enables autostart with the requested priority' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'new' => { 'enable' => true, 'priority' => 250 },
      'original' => { 'enable' => false, 'priority' => nil },
      'revert' => true
    )

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set autostart],
      101,
      { priority: 250 }
    )
  end

  it 'disables autostart when reverting to a disabled original state' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'new' => { 'enable' => true, 'priority' => 250 },
      'original' => { 'enable' => false, 'priority' => nil },
      'revert' => true
    )

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct unset autostart], 101)
  end

  it 'is a no-op on rollback when revert is disabled' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'new' => { 'enable' => false, 'priority' => nil },
      'original' => { 'enable' => true, 'priority' => 100 },
      'revert' => false
    )

    allow(cmd).to receive(:osctl)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).not_to have_received(:osctl)
  end
end
