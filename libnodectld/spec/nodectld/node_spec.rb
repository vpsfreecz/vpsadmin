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
end
