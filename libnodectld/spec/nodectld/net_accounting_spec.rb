# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/net_accounting'
require 'nodectld/net_accounting/interface'

RSpec.describe NodeCtld::NetAccounting do
  before do
    stub_node_bunny
  end

  def build_accounting
    described_class.send(:new)
  end

  it 'adds, renames, removes, removes by VPS, and chowns interfaces' do
    accounting = build_accounting

    accounting.add_netif(101, 5, 1, 'eth0')
    accounting.add_netif(102, 6, 2, 'eth0')
    accounting.rename_netif(101, 1, 'wan0')
    accounting.chown_vps(101, 9)
    accounting.remove_netif(102, 2)

    expect(accounting.dump).to contain_exactly(
      include(vps_id: 101, user_id: 9, netif_id: 1, vps_name: 'wan0')
    )

    accounting.remove_vps(101)

    expect(accounting.dump).to eq([])
  end

  it 'queues discovery requests for newly-up interfaces' do
    accounting = build_accounting
    queue = accounting.instance_variable_get(:@discovery_queue)

    accounting.netif_up(101, 'eth0')

    expect(queue.pop(timeout: 0)).to eq([:up, 101, 'eth0'])
  end

  it 'converts fetched RPC network interfaces' do
    accounting = build_accounting
    rpc = double(
      list_vps_network_interfaces: [
        {
          'vps_id' => 101,
          'user_id' => 5,
          'id' => 9,
          'name' => 'eth0',
          'bytes_in_readout' => 100,
          'bytes_out_readout' => 200,
          'packets_in_readout' => 10,
          'packets_out_readout' => 20
        }
      ]
    )

    allow(NodeCtld::RpcClient).to receive(:run).and_yield(rpc)

    expect(accounting.send(:fetch_netifs).map(&:dump)).to contain_exactly(
      include(
        vps_id: 101,
        user_id: 5,
        netif_id: 9,
        vps_name: 'eth0',
        last_bytes_in: 100,
        last_bytes_out: 200
      )
    )
  end

  it 'discovers a missing interface through the RPC client' do
    accounting = build_accounting
    rpc = double(
      find_vps_network_interface: {
        'vps_id' => 101,
        'user_id' => 5,
        'id' => 9,
        'name' => 'eth0'
      }
    )

    allow(NodeCtld::RpcClient).to receive(:run).and_yield(rpc)
    accounting.send(:discover_netif, 101, 'eth0')

    expect(accounting.dump).to contain_exactly(
      include(vps_id: 101, user_id: 5, netif_id: 9, vps_name: 'eth0')
    )
  end
end
