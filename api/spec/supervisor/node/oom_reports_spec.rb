# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::OomReports do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:supervisor) { described_class.new(nil, SpecSeed.node) }

  def create_vps!
    build_standalone_vps_fixture(user: SpecSeed.user, node: SpecSeed.node).fetch(:vps)
  end

  def seed_high_rate_reports!(vps, count: described_class::THRESHOLD)
    count.times do |i|
      create_oom_report_fixture!(
        vps:,
        count: described_class::HIGHRATE,
        created_at: (i + 1).minutes.ago
      )
    end
  end

  describe '#start' do
    it 'ignores reports for VPSes on another node without dereferencing nil' do
      foreign_vps = build_standalone_vps_fixture(user: SpecSeed.user, node: SpecSeed.other_node).fetch(:vps)
      channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
      described_class.new(channel, SpecSeed.node).start
      queue = channel.queues.fetch("node:#{SpecSeed.node.domain_name}:oom_reports")

      expect do
        queue.publish(build_oom_report_payload(vps: foreign_vps, count: described_class::THRESHOLD).to_json)
      end.not_to raise_error

      expect(OomReport.where(vps: foreign_vps)).to be_empty
    end
  end

  describe '#save_report' do
    it 'creates report, usage, stat, task and counter rows with unsigned UIDs' do
      vps = create_vps!
      payload = build_oom_report_payload(vps:, count: 7)
      payload.fetch('tasks').first.update(
        'uid' => 2_147_756_930,
        'vps_uid' => (2**32) - 2
      )

      report = supervisor.send(:save_report, payload)

      expect(report).to be_persisted
      expect(report.count).to eq(7)
      expect(report.oom_report_usages.pluck(:memtype, :usage, :limit, :failcnt)).to eq(
        [['memory', 1024.to_d, 2048.to_d, 3.to_d]]
      )
      expect(report.oom_report_stats.pluck(:parameter, :value)).to contain_exactly(
        ['cache', 10.to_d],
        ['rss', 20.to_d]
      )
      expect(report.oom_report_tasks.pluck(:host_pid, :vps_pid, :name, :host_uid, :vps_uid)).to eq(
        [[300, 30, 'worker', 2_147_756_930, (2**32) - 2]]
      )
      expect(OomReportCounter.find_by!(vps:, cgroup: payload.fetch('cgroup')).counter).to eq(7)
    end

    it 'identifies out-of-range task fields and preserves the original exception' do
      vps = create_vps!
      payload = build_oom_report_payload(vps:)
      task = payload.fetch('tasks').first
      payload['tasks'] = Array.new(11) do |i|
        task.merge('pid' => 2_147_483_648 + i)
      end

      expect do
        supervisor.send(:save_report, payload)
      end.to raise_error(described_class::TaskRangeError) do |error|
        expect(error.message).to include(
          "for VPS ##{vps.id}",
          '11 task(s)',
          'task[0].host_pid=2147483648',
          'task[9].host_pid=2147483657',
          '1 more'
        )
        expect(error.message).not_to include('task[10].host_pid')
        expect(error.cause).to be_a(ActiveModel::RangeError)
      end
    end

    it 'does not let diagnostic failures hide the original range error' do
      vps = create_vps!
      payload = build_oom_report_payload(vps:)
      payload.fetch('tasks').first['pid'] = 2_147_483_648
      allow(supervisor).to receive(:task_range_error_message).and_raise('diagnostics exploded')

      expect do
        supervisor.send(:save_report, payload)
      end.to raise_error(described_class::TaskRangeError) do |error|
        expect(error.message).to include(
          'diagnostics failed: RuntimeError: diagnostics exploded'
        )
        expect(error.cause).to be_a(ActiveModel::RangeError)
      end
    end

    it 'increments matching rule hit count and marks ignored reports' do
      vps = create_vps!
      rule = OomReportRule.create!(
        vps:,
        action: :ignore,
        cgroup_pattern: '/user.slice/*',
        hit_count: 0
      )

      report = supervisor.send(:save_report, build_oom_report_payload(vps:, cgroup: '/user.slice/a.scope'))

      expect(rule.reload.hit_count).to eq(1)
      expect(report.oom_report_rule).to eq(rule)
      expect(report.ignored).to be(true)
    end
  end

  describe '#evaluate_rules' do
    it 'returns the first matching rule in rule order' do
      vps = create_vps!
      first = OomReportRule.create!(vps:, action: :notify, cgroup_pattern: '/user.slice/*')
      OomReportRule.create!(vps:, action: :ignore, cgroup_pattern: '/user.slice/a.scope')

      expect(supervisor.send(:evaluate_rules, vps, '/user.slice/a.scope')).to eq(first)
    end
  end

  describe '#handle_abuser' do
    before do
      allow(TransactionChains::Vps::OomPrevention).to receive(:fire2)
    end

    it 'does nothing for non-running VPSes' do
      vps = create_vps!
      seed_high_rate_reports!(vps)

      supervisor.send(:handle_abuser, vps)

      expect(TransactionChains::Vps::OomPrevention).not_to have_received(:fire2)
    end

    it 'does nothing when the high-rate threshold is not met' do
      vps = create_vps!
      set_vps_running!(vps)
      seed_high_rate_reports!(vps, count: described_class::THRESHOLD - 1)

      supervisor.send(:handle_abuser, vps)

      expect(TransactionChains::Vps::OomPrevention).not_to have_received(:fire2)
    end

    it 'chooses restart for the first prevention window' do
      vps = create_vps!
      set_vps_running!(vps)
      seed_high_rate_reports!(vps)

      supervisor.send(:handle_abuser, vps)

      expect(TransactionChains::Vps::OomPrevention).to have_received(:fire2).with(
        kwargs: hash_including(vps:, action: :restart)
      )
    end

    it 'escalates to stop after repeated recent preventions' do
      vps = create_vps!
      set_vps_running!(vps)
      seed_high_rate_reports!(vps)
      3.times do |i|
        OomPrevention.create!(
          vps:,
          action: :restart,
          created_at: (10 + i).minutes.ago,
          updated_at: (10 + i).minutes.ago
        )
      end

      supervisor.send(:handle_abuser, vps)

      expect(TransactionChains::Vps::OomPrevention).to have_received(:fire2).with(
        kwargs: hash_including(vps:, action: :stop)
      )
    end

    it 'swallows and logs ResourceLocked from OomPrevention' do
      vps = create_vps!
      set_vps_running!(vps)
      seed_high_rate_reports!(vps)
      allow(TransactionChains::Vps::OomPrevention).to receive(:fire2)
        .and_raise(ResourceLocked.new(vps, 'locked'))

      expect do
        supervisor.send(:handle_abuser, vps)
      end.to output(/VPS #{vps.id} locked, would restart otherwise/).to_stdout
    end
  end
end
