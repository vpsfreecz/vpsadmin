# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/start'
require 'nodectld/vps'

RSpec.describe NodeCtld::Commands::Vps::Start do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'start_timeout' => 45,
      'autostart_priority' => 250,
      'rollback_start' => true
    )
  end

  it 'starts the VPS through NodeCtld::Vps' do
    vps = stub_vps_instance(101, start: { ret: :ok })

    expect(cmd.exec).to eq(ret: :ok)
    expect(vps).to have_received(:start).with(45, 250)
  end

  it 'stops the VPS on rollback when rollback_start is enabled' do
    vps = stub_vps_instance(101, stop: { ret: :ok })

    expect(cmd.rollback).to eq(ret: :ok)
    expect(vps).to have_received(:stop)
  end

  it 'is a no-op on rollback when rollback_start is disabled' do
    no_rollback_cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'rollback_start' => false
    )

    allow(NodeCtld::Vps).to receive(:new)

    expect(no_rollback_cmd.rollback).to eq(ret: :ok)
    expect(NodeCtld::Vps).not_to have_received(:new)
  end
end
