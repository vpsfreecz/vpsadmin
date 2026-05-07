# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/node_status'
require 'nodectld/queues'

RSpec.describe NodeCtld::NodeStatus do
  def stub_probes(arc: true)
    cpu_usage = instance_double(NodeCtld::SystemProbes::CpuUsage, start: nil, values: { user: 12.5, idle: 87.5 })
    memory = instance_double(
      NodeCtld::SystemProbes::Memory,
      total: 1024,
      used: 512,
      swap_total: 256,
      swap_used: 64
    )

    allow(NodeCtld::SystemProbes::Cpus).to receive(:new).and_return(double(count: 4))
    allow(NodeCtld::SystemProbes::CpuUsage).to receive(:new).and_return(cpu_usage)
    allow(NodeCtld::SystemProbes::Memory).to receive(:new).and_return(memory)
    allow(NodeCtld::SystemProbes::Kernel).to receive(:new).and_return(double(version: '6.1.0'))
    allow(NodeCtld::SystemProbes::Uptime).to receive(:new).and_return(double(uptime: 123.4))
    allow(NodeCtld::SystemProbes::LoadAvg).to receive(:new).and_return(double(avg: { 1 => 0.1, 5 => 0.2, 15 => 0.3 }))

    if arc
      allow(NodeCtld::SystemProbes::Arc).to receive(:new).and_return(
        double(c_max: 100, c: 80, size: 70, hit_percent: 90.5)
      )
    else
      allow(NodeCtld::SystemProbes::Arc).to receive(:new)
    end
  end

  def published_status(pool_status, status: described_class.new(pool_status))
    published = []

    allow(NodeCtld::NodeBunny).to receive(:publish_drop) do |_exchange, payload, **_opts|
      published << JSON.parse(payload)
    end

    status.update
    published.fetch(0)
  end

  before do
    stub_node_bunny
    allow(File).to receive(:read).and_call_original
  end

  it 'publishes node status with ARC and cgroup version on node/storage types' do
    $CFG = runtime_cfg(vpsadmin: { node_id: 44, type: :node })
    pool_status = double(summary_values: [Time.at(100), :online, :scrub, 12.5])

    stub_probes
    allow(File).to receive(:read).with('/run/osctl/cgroup.version').and_return("2\n")

    payload = published_status(pool_status)

    expect(payload).to include(
      'id' => 44,
      'vpsadmin_version' => NodeCtld::VERSION,
      'kernel' => '6.1.0',
      'cgroup_version' => 2,
      'uptime' => 123,
      'cpus' => 4,
      'cpu' => { 'user' => 12.5, 'idle' => 87.5 },
      'memory' => { 'total' => 1024, 'used' => 512 },
      'swap' => { 'total' => 256, 'used' => 64 },
      'arc' => { 'c_max' => 100, 'c' => 80, 'size' => 70, 'hitpercent' => 90.5 },
      'loadavg' => { '1' => 0.1, '5' => 0.2, '15' => 0.3 },
      'storage' => {
        'state' => 'online',
        'scan' => 'scrub',
        'scan_percent' => 12.5,
        'checked_at' => 100
      }
    )
  end

  it 'omits ARC outside node/storage roles' do
    $CFG = runtime_cfg(vpsadmin: { type: :dns })
    pool_status = double(summary_values: [Time.at(100), :online, :none, nil])

    stub_probes(arc: false)
    allow(File).to receive(:read).with('/run/osctl/cgroup.version').and_return("2\n")

    expect(published_status(pool_status)['arc']).to be_nil
    expect(NodeCtld::SystemProbes::Arc).not_to have_received(:new)
  end

  it 'falls back to cgroup version 0 when the runtime file is missing' do
    $CFG = runtime_cfg(vpsadmin: { type: :node })
    pool_status = double(summary_values: [Time.at(100), :online, :none, nil])

    stub_probes
    allow(File).to receive(:read).with('/run/osctl/cgroup.version').and_raise(Errno::ENOENT)
    status = described_class.new(pool_status)

    allow(status).to receive(:log)

    expect(published_status(pool_status, status: status)['cgroup_version']).to eq(0)
  end
end
