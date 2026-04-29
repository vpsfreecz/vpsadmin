# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::NetMonitor do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 15, 0, 0) }

  def monitor_payload(netif, overrides = {})
    {
      'id' => netif.id,
      'time' => timestamp.to_i,
      'bytes_in' => 100,
      'bytes_out' => 250,
      'packets_in' => 10,
      'packets_out' => 25,
      'delta' => 60,
      'bytes_in_readout' => 10_000,
      'bytes_out_readout' => 20_000,
      'packets_in_readout' => 1000,
      'packets_out_readout' => 2000
    }.merge(overrides)
  end

  describe '#update_monitors' do
    it 'upserts aggregate and directional counters' do
      netif = create_netif_vps_fixture!(node:).fetch(:netif)

      supervisor.send(:update_monitors, [monitor_payload(netif)])

      monitor = NetworkInterfaceMonitor.find_by!(network_interface: netif)
      expect(monitor.bytes).to eq(350)
      expect(monitor.bytes_in).to eq(100)
      expect(monitor.bytes_out).to eq(250)
      expect(monitor.packets).to eq(35)
      expect(monitor.packets_in).to eq(10)
      expect(monitor.packets_out).to eq(25)
      expect(monitor.delta).to eq(60)
      expect(monitor.bytes_in_readout).to eq(10_000)
      expect(monitor.bytes_out_readout).to eq(20_000)
      expect(monitor.created_at).to eq(timestamp)
      expect(monitor.updated_at).to eq(timestamp)
    end

    it 'replaces the current snapshot on repeated updates' do
      netif = create_netif_vps_fixture!(node:).fetch(:netif)
      supervisor.send(:update_monitors, [monitor_payload(netif)])

      supervisor.send(
        :update_monitors,
        [
          monitor_payload(
            netif,
            'time' => (timestamp + 60).to_i,
            'bytes_in' => 500,
            'bytes_out' => 700,
            'packets_in' => 50,
            'packets_out' => 70
          )
        ]
      )

      expect(NetworkInterfaceMonitor.where(network_interface: netif).count).to eq(1)
      monitor = NetworkInterfaceMonitor.find_by!(network_interface: netif)
      expect(monitor.bytes).to eq(1200)
      expect(monitor.packets).to eq(120)
      expect(monitor.created_at).to eq(timestamp)
      expect(monitor.updated_at).to eq(timestamp + 60)
    end
  end
end
