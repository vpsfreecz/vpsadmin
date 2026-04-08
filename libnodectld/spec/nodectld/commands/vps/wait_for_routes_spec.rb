# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/wait_for_routes'

RSpec.describe NodeCtld::Commands::Vps::WaitForRoutes do
  let(:driver) { build_vps_driver }
  let(:route_check_class) { Class.new }

  before do
    stub_const('NodeCtld::RouteCheck', route_check_class)
    allow(route_check_class).to receive(:wait)
  end

  it 'waits for routes on exec when configured for execute' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'vps_id' => 101,
      'timeout' => 30,
      'direction' => 'execute'
    )

    expect(cmd.exec).to eq(ret: :ok)
    expect(route_check_class).to have_received(:wait).with('tank/ct', 101, timeout: 30)
  end

  it 'waits for routes on rollback when configured for rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'vps_id' => 101,
      'timeout' => 45,
      'direction' => 'rollback'
    )

    expect(cmd.rollback).to eq(ret: :ok)
    expect(route_check_class).to have_received(:wait).with('tank/ct', 101, timeout: 45)
  end

  it 'is a no-op when the direction does not match the current phase' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'vps_id' => 101,
      'timeout' => 30,
      'direction' => 'execute'
    )

    expect(cmd.rollback).to eq(ret: :ok)
    expect(route_check_class).not_to have_received(:wait)
  end
end
