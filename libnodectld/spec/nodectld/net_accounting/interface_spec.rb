# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/net_accounting'
require 'nodectld/net_accounting/interface'

RSpec.describe NodeCtld::NetAccounting::Interface do
  let(:reader) { instance_double(OsCtl::Lib::NetifStats) }

  before do
    allow(OsCtl::Lib::NetifStats).to receive(:new).and_return(reader)
    allow(reader).to receive(:reset)
  end

  it 'computes deltas from interface readouts' do
    allow(reader).to receive(:get_stats_for).with('veth101').and_return(
      tx: { bytes: 160, packets: 16 },
      rx: { bytes: 260, packets: 26 }
    )

    netif = described_class.new(101, 5, 9, 'eth0', bytes_in: 100, bytes_out: 200, packets_in: 10, packets_out: 20)

    expect(netif.changed?).to be(false)

    netif.update('veth101')

    expect(netif.changed?).to be(true)
    expect(netif.dump).to include(
      bytes_in: 60,
      bytes_out: 60,
      packets_in: 6,
      packets_out: 6,
      log_bytes_in: 60,
      log_bytes_out: 60
    )
  end

  it 'exports monitor data and resets the changed flag' do
    allow(reader).to receive(:get_stats_for).and_return(
      tx: { bytes: 10, packets: 1 },
      rx: { bytes: 20, packets: 2 }
    )
    netif = described_class.new(101, 5, 9, 'eth0')

    netif.update('veth101')
    monitor = netif.export_monitor

    expect(monitor).to include(
      id: 9,
      bytes_in: 10,
      bytes_out: 20,
      packets_in: 1,
      packets_out: 2,
      bytes_in_readout: 10,
      bytes_out_readout: 20
    )
    expect(netif.changed?).to be(false)
  end

  it 'exports accounting data and resets logged counters' do
    allow(reader).to receive(:get_stats_for).and_return(
      tx: { bytes: 10, packets: 1 },
      rx: { bytes: 20, packets: 2 }
    )
    netif = described_class.new(101, 5, 9, 'eth0')

    netif.update('veth101')

    expect(netif.export_accounting?(0)).to be(true)
    expect(netif.export_accounting).to include(
      id: 9,
      user_id: 5,
      bytes_in: 10,
      bytes_out: 20,
      packets_in: 1,
      packets_out: 2
    )
    expect(netif.dump).to include(
      log_bytes_in: 0,
      log_bytes_out: 0,
      log_packets_in: 0,
      log_packets_out: 0
    )
  end
end
