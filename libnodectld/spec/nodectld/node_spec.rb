# frozen_string_literal: true

require 'nodectld/node'

RSpec.describe NodeCtld::Node do
  it 'creates the download healthcheck file when a pool becomes ready' do
    node = described_class.new
    pool = described_class::Pool.new(123, 'tank', 'tank', :hypervisor, false)

    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with('/run/service/pool-tank/done').and_return(true)
    allow(node).to receive(:osctl_parse).with(%i[pool show], 'tank').and_return(state: 'active')
    allow(node).to receive(:ensure_pool_download_healthcheck)
    allow(node).to receive(:install_pool_hooks)
    allow(node).to receive(:log)

    node.send(:wait_for_pool, pool)

    expect(node).to have_received(:ensure_pool_download_healthcheck).with('tank', 123)
  end

  it 'creates download healthcheck files for all pools on the same zpool' do
    node = described_class.new
    pools = [
      described_class::Pool.new(123, 'storage', 'storage/vpsfree.cz/nas', :hypervisor, false),
      described_class::Pool.new(456, 'storage', 'storage/vpsfree.cz/backup', :hypervisor, false)
    ]

    allow(node).to receive(:fetch_pools).and_return(pools)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with('/run/service/pool-storage/done').and_return(true)
    allow(node).to receive(:osctl_parse).with(%i[pool show], 'storage').and_return(state: 'active')
    allow(node).to receive(:ensure_pool_download_healthcheck)
    allow(node).to receive(:install_pool_hooks)
    allow(node).to receive(:log)

    node.init

    expect(node).to have_received(:ensure_pool_download_healthcheck).with(
      'storage/vpsfree.cz/nas',
      123
    )
    expect(node).to have_received(:ensure_pool_download_healthcheck).with(
      'storage/vpsfree.cz/backup',
      456
    )
  end

  it 'updates all pools on the same zpool when pool hooks report import or export' do
    node = described_class.new
    pools = {
      123 => described_class::Pool.new(123, 'storage', 'storage/vpsfree.cz/nas', :hypervisor, true),
      456 => described_class::Pool.new(
        456,
        'storage',
        'storage/vpsfree.cz/backup',
        :hypervisor,
        true
      )
    }

    node.instance_variable_set(:@pools, pools)

    node.pool_down('storage')
    expect(pools.values).to all(have_attributes(online: false))

    node.pool_up('storage')
    expect(pools.values).to all(have_attributes(online: true))
  end
end
