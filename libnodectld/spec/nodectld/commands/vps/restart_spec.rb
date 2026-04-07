# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/restart'
require 'nodectld/vps'

RSpec.describe NodeCtld::Commands::Vps::Restart do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'start_timeout' => 60,
      'autostart_priority' => 320,
      'kill' => true
    )
  end

  it 'restarts the VPS through NodeCtld::Vps and keeps rollback as a no-op' do
    vps = stub_vps_instance(101, restart: nil)

    expect(cmd.exec).to eq(ret: :ok)
    expect(vps).to have_received(:restart).with(60, 320, kill: true)
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
