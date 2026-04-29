# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::Status do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 12, 0, 0) }
  let(:now) { Time.utc(2026, 4, 5, 12, 30, 0) }

  def payload(overrides = {})
    {
      'id' => node.id,
      'time' => timestamp.to_i,
      'uptime' => 3600,
      'nproc' => 42,
      'loadavg' => { '1' => 0.5, '5' => 0.25, '15' => 0.1 },
      'vpsadmin_version' => 'spec',
      'kernel' => '6.8.0',
      'cgroup_version' => NodeCurrentStatus.cgroup_versions[:cgroup_v2],
      'cpus' => 8,
      'cpu' => {
        'user' => 10.0,
        'nice' => 0.0,
        'system' => 5.0,
        'idle' => 80.0,
        'iowait' => 2.0,
        'irq' => 1.0,
        'softirq' => 1.0,
        'guest' => 0.0
      },
      'memory' => { 'total' => 8 * 1024 * 1024, 'used' => 4 * 1024 * 1024 },
      'swap' => { 'total' => 2 * 1024 * 1024, 'used' => 1 * 1024 * 1024 },
      'storage' => {
        'state' => 'online',
        'scan' => 'none',
        'scan_percent' => nil,
        'checked_at' => timestamp.to_i
      },
      'arc' => {
        'c_max' => 512 * 1024 * 1024,
        'c' => 256 * 1024 * 1024,
        'size' => 128 * 1024 * 1024,
        'hitpercent' => 95.5
      }
    }.merge(overrides)
  end

  before do
    allow(Time).to receive(:now).and_return(now)
  end

  describe '#start' do
    it 'ignores payloads for other nodes' do
      channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
      described_class.new(channel, node).start

      queue = channel.queues.fetch("node:#{node.domain_name}:statuses")
      queue.publish(payload('id' => node.id + 10_000).to_json)

      expect(NodeCurrentStatus.where(node:)).not_to exist
    end
  end

  describe '#update_status' do
    it 'stores current status values in MiB and logs the first sample' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      supervisor.send(:update_status, current, payload)

      current.reload
      expect(current.uptime).to eq(3600)
      expect(current.process_count).to eq(42)
      expect(current.total_memory).to eq(8192)
      expect(current.used_memory).to eq(4096)
      expect(current.total_swap).to eq(2048)
      expect(current.used_swap).to eq(1024)
      expect(current.arc_c_max).to eq(512)
      expect(current.arc_c).to eq(256)
      expect(current.arc_size).to eq(128)
      expect(current.arc_hitpercent).to eq(95.5)
      expect(current.pool_state).to eq('online')
      expect(current.pool_scan).to eq('none')
      expect(current.pool_checked_at).to eq(timestamp)
      expect(current.last_log_at).to eq(now)
      expect(current.update_count).to eq(1)

      log = NodeStatus.find_by!(node:)
      expect(log.created_at).to eq(timestamp)
      expect(log.process_count).to eq(42)
      expect(log.used_memory).to eq(4096)
    end

    it 'clears ARC values when the payload omits ARC data' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      supervisor.send(:update_status, current, payload)

      current.reload
      supervisor.send(:update_status, current, payload('arc' => nil))

      current.reload
      expect(current.arc_c_max).to be_nil
      expect(current.arc_c).to be_nil
      expect(current.arc_size).to be_nil
      expect(current.arc_hitpercent).to be_nil
    end

    it 'updates rolling sums and update count between log intervals' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      supervisor.send(:update_status, current, payload)

      current.reload
      next_sample = payload(
        'time' => (timestamp + 60).to_i,
        'nproc' => 58,
        'memory' => { 'total' => 8 * 1024 * 1024, 'used' => 5 * 1024 * 1024 },
        'swap' => { 'total' => 2 * 1024 * 1024, 'used' => 512 * 1024 },
        'cpu' => payload.fetch('cpu').merge('user' => 12.0)
      )

      supervisor.send(:update_status, current, next_sample)

      current.reload
      expect(current.update_count).to eq(2)
      expect(current.sum_process_count).to eq(100)
      expect(current.sum_used_memory).to eq(9216)
      expect(current.sum_used_swap).to eq(1536)
      expect(current.sum_cpu_user).to eq(22.0)
      expect(NodeStatus.where(node:).count).to eq(1)
    end
  end
end
