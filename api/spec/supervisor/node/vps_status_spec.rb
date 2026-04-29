# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::VpsStatus do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 13, 0, 0) }
  let(:now) { Time.utc(2026, 4, 5, 13, 15, 0) }

  def status_payload(vps, overrides = {})
    {
      'id' => vps.id,
      'time' => timestamp.to_i,
      'status' => true,
      'running' => true,
      'in_rescue_mode' => false,
      'uptime' => 7200,
      'loadavg' => { '1' => 0.4, '5' => 0.3, '15' => 0.2 },
      'process_count' => 31,
      'used_memory' => 512 * 1024 * 1024,
      'cpu_usage' => 40.0,
      'hostname' => 'runtime-hostname'
    }.merge(overrides)
  end

  before do
    allow(Time).to receive(:now).and_return(now)
  end

  describe '#start' do
    it 'does not update VPSes assigned to a different node' do
      other_vps = build_standalone_vps_fixture(node: SpecSeed.other_node).fetch(:vps)
      channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
      described_class.new(channel, node).start

      queue = channel.queues.fetch("node:#{node.domain_name}:vps_statuses")
      queue.publish(status_payload(other_vps).to_json)

      expect(VpsCurrentStatus.where(vps: other_vps)).not_to exist
    end
  end

  describe '#update_status' do
    it 'creates current status with runtime flags and metrics' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      current = VpsCurrentStatus.find_or_initialize_by(vps:)

      supervisor.send(:update_status, current, status_payload(vps))

      current.reload
      expect(current.status).to be(true)
      expect(current.is_running).to be(true)
      expect(current.in_rescue_mode).to be(false)
      expect(current.cpus).to eq(2)
      expect(current.total_memory).to eq(2048)
      expect(current.total_swap).to eq(0)
      expect(current.uptime).to eq(7200)
      expect(current.loadavg1).to eq(0.4)
      expect(current.process_count).to eq(31)
      expect(current.used_memory).to eq(512)
      expect(current.cpu_idle).to eq(80.0)
      expect(current.last_log_at).to eq(now)
      expect(current.update_count).to eq(1)
      expect(vps.reload.hostname).to eq('runtime-hostname')

      log = VpsStatus.find_by!(vps:)
      expect(log.created_at).to eq(timestamp)
      expect(log.is_running).to be(true)
      expect(log.used_memory).to eq(512)
    end

    it 'tolerates missing load averages while the VPS is running' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      current = VpsCurrentStatus.find_or_initialize_by(vps:)

      expect do
        supervisor.send(:update_status, current, status_payload(vps, 'loadavg' => nil))
      end.not_to raise_error

      current.reload
      expect(current.loadavg1).to be_nil
      expect(current.loadavg5).to be_nil
      expect(current.loadavg15).to be_nil
    end

    it 'clears runtime-only metrics when the VPS is stopped' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      current = set_vps_running!(vps)
      current.update!(
        uptime: 10,
        loadavg1: 1.0,
        loadavg5: 1.0,
        loadavg15: 1.0,
        process_count: 9,
        used_memory: 128,
        cpu_idle: 50.0
      )

      supervisor.send(
        :update_status,
        current,
        status_payload(vps, 'status' => true, 'running' => false)
      )

      current.reload
      expect(current.status).to be(true)
      expect(current.is_running).to be(false)
      expect(current.uptime).to be_nil
      expect(current.loadavg1).to be_nil
      expect(current.process_count).to be_nil
      expect(current.used_memory).to be_nil
      expect(current.cpu_idle).to be_nil
    end

    it 'adds rolling sums between log intervals' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      current = VpsCurrentStatus.find_or_initialize_by(vps:)
      supervisor.send(:update_status, current, status_payload(vps))

      current.reload
      supervisor.send(
        :update_status,
        current,
        status_payload(
          vps,
          'time' => (timestamp + 60).to_i,
          'process_count' => 39,
          'used_memory' => 1024 * 1024 * 1024,
          'cpu_usage' => 20.0
        )
      )

      current.reload
      expect(current.update_count).to eq(2)
      expect(current.sum_process_count).to eq(70)
      expect(current.sum_used_memory).to eq(1536)
      expect(current.sum_cpu_idle).to eq(170.0)
      expect(VpsStatus.where(vps:).count).to eq(1)
    end
  end
end
