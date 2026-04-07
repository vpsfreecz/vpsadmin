# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/stop'
require 'nodectld/vps'

RSpec.describe NodeCtld::Commands::Vps::Stop do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'kill' => true,
      'rollback_stop' => true,
      'start_timeout' => 30,
      'autostart_priority' => 180
    )
  end

  it 'stops the VPS and passes through the kill flag' do
    vps = stub_vps_instance(101, stop: nil)

    expect(cmd.exec).to eq(ret: :ok)
    expect(vps).to have_received(:stop).with(kill: true)
  end

  it 'starts the VPS on rollback when rollback_stop is enabled' do
    vps = stub_vps_instance(101, start: nil)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(vps).to have_received(:start).with(30, 180)
  end

  it 'is a no-op on rollback when rollback_stop is disabled' do
    no_rollback_cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'rollback_stop' => false
    )

    allow(NodeCtld::Vps).to receive(:new)

    expect(no_rollback_cmd.rollback).to eq(ret: :ok)
    expect(NodeCtld::Vps).not_to have_received(:new)
  end
end
