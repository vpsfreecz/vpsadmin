# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/populate_config'
require 'nodectld/vps_config'
require 'nodectld/vps_config/network_interface'
require 'nodectld/vps_config/route'

RSpec.describe NodeCtld::Commands::Vps::PopulateConfig do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'vps_id' => 101,
      'network_interfaces' => [
        {
          'name' => 'eth0',
          'routes' => [
            { 'addr' => '192.0.2.10', 'prefix' => 24, 'via' => '192.0.2.1' },
            { 'addr' => '2001:db8::10', 'prefix' => 64, 'via' => 'fe80::1' }
          ]
        },
        {
          'name' => 'eth1',
          'routes' => []
        }
      ]
    )
  end

  it 'creates the VPS config with the expected interfaces and routes' do
    cfg = Struct.new(:network_interfaces).new([])

    allow(NodeCtld::VpsConfig).to receive(:create_or_replace).with('tank/ct', 101).and_yield(cfg)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cfg.network_interfaces.map(&:name)).to eq(%w[eth0 eth1])
    expect(cfg.network_interfaces[0].routes[4].map(&:via)).to eq(['192.0.2.1'])
    expect(cfg.network_interfaces[0].routes[4].map { |route| route.address.to_string }).to eq(
      ['192.0.2.10/24']
    )
    expect(cfg.network_interfaces[0].routes[6].map(&:via)).to eq(['fe80::1'])
    expect(cfg.network_interfaces[0].routes[6].map { |route| route.address.to_string }).to eq(
      ['2001:db8::10/64']
    )
    expect(cfg.network_interfaces[1].routes).to eq({ 4 => [], 6 => [] })
  end

  it 'destroys the generated config on rollback when it exists' do
    cfg_class = stub_const('PopulateConfigRollbackConfig', Class.new do
      def exist?; end

      def destroy(backup: true); end
    end)
    cfg = instance_double(cfg_class, exist?: true)

    allow(cfg).to receive(:destroy)
    allow(NodeCtld::VpsConfig).to receive(:open).with('tank/ct', 101).and_return(cfg)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cfg).to have_received(:destroy).with(backup: false)
  end
end
