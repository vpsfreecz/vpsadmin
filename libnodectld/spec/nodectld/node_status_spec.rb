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
    evidence = double(
      values: { 'schema_version' => 1 },
      report_published: nil
    )
    allow(NodeCtld::SystemProbes::SecurityEvidence).to receive(:new).and_return(evidence)

    if arc
      allow(NodeCtld::SystemProbes::Arc).to receive(:new).and_return(
        double(c_max: 100, c: 80, size: 70, hit_percent: 90.5)
      )
    else
      allow(NodeCtld::SystemProbes::Arc).to receive(:new)
    end

    evidence
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

    evidence = stub_probes
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
      },
      'security_evidence' => { 'schema_version' => 1 }
    )
    expect(evidence).to have_received(:report_published)
  end

  it 'omits ARC and all kernel evidence outside node/storage roles' do
    $CFG = runtime_cfg(vpsadmin: { type: :dns_server })
    pool_status = double(summary_values: [Time.at(100), :online, :none, nil])

    stub_probes(arc: false)
    allow(File).to receive(:read).with('/run/osctl/cgroup.version').and_return("2\n")

    payload = published_status(pool_status)

    expect(payload['arc']).to be_nil
    expect(payload['kernel']).to be_nil
    expect(payload).not_to have_key('security_evidence')
    expect(NodeCtld::SystemProbes::Arc).not_to have_received(:new)
    expect(NodeCtld::SystemProbes::Kernel).not_to have_received(:new)
    expect(NodeCtld::SystemProbes::SecurityEvidence).not_to have_received(:new)
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

  it 'refreshes CPU count and cgroup version for every status update' do
    $CFG = runtime_cfg(vpsadmin: { node_id: 44, type: :node })
    pool_status = double(summary_values: [Time.at(100), :online, :none, nil])

    stub_probes
    allow(NodeCtld::SystemProbes::Cpus).to receive(:new).and_return(
      double(count: 4),
      double(count: 8)
    )
    allow(File).to receive(:read).with('/run/osctl/cgroup.version').and_return("1\n", "2\n")
    status = described_class.new(pool_status)

    first = published_status(pool_status, status: status)
    second = published_status(pool_status, status: status)

    expect(first).to include('cpus' => 4, 'cgroup_version' => 1)
    expect(second).to include('cpus' => 8, 'cgroup_version' => 2)
  end

  it 'does not advance periodic evidence reporting when the status is dropped' do
    $CFG = runtime_cfg(vpsadmin: { node_id: 44, type: :node })
    pool_status = double(summary_values: [Time.at(100), :online, :none, nil])
    evidence = stub_probes
    allow(File).to receive(:read).with('/run/osctl/cgroup.version').and_return("2\n")
    allow(NodeCtld::NodeBunny).to receive(:publish_drop).and_return(nil)

    described_class.new(pool_status).update

    expect(evidence).not_to have_received(:report_published)
  end
end
