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
    allow(node).to receive(:install_daemon_hooks)
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

  it 'installs osctld daemon hooks' do
    tmpdir = Dir.mktmpdir('node-daemon-hook-spec')
    node = described_class.new

    stub_const('NodeCtld::Node::DAEMON_HOOK_DIR', tmpdir)

    node.send(:install_daemon_hooks)

    hook_path = File.join(tmpdir, 'pre-stop')
    expect(File.file?(hook_path)).to be(true)
    expect(File.stat(hook_path).mode & 0o777).to eq(0o500)
    expect(File.read(hook_path)).to include('NodeCtld::DaemonHook.pre_stop(ENV)')
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it 'skips osctld daemon hook installation when the runtime directory is absent' do
    tmpdir = Dir.mktmpdir('node-daemon-hook-spec')
    hook_dir = File.join(tmpdir, 'missing')
    node = described_class.new

    stub_const('NodeCtld::Node::DAEMON_HOOK_DIR', hook_dir)
    allow(node).to receive(:log)

    node.send(:install_daemon_hooks)

    expect(node).to have_received(:log).with(
      :warn,
      "osctld daemon hook dir not found at #{hook_dir.inspect}"
    )
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it 'skips osctld daemon hook installation outside hypervisor nodes' do
    tmpdir = Dir.mktmpdir('node-daemon-hook-spec')
    node = described_class.new

    $CFG.patch(vpsadmin: { type: :dns_server })
    stub_const('NodeCtld::Node::DAEMON_HOOK_DIR', tmpdir)
    allow(FileUtils).to receive(:cp)

    node.send(:install_daemon_hooks)

    expect(FileUtils).not_to have_received(:cp)
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
