# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::OomReport do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  def create_vps!
    build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
  end

  describe '#notify' do
    before do
      allow(TransactionChains::Vps::OomReports).to receive(:fire2)
    end

    it 'selects VPSes with unreported non-ignored reports' do
      selected_vps = create_vps!
      ignored_vps = create_vps!
      reported_vps = create_vps!
      create_oom_report_fixture!(vps: selected_vps, ignored: false, reported_at: nil)
      create_oom_report_fixture!(vps: ignored_vps, ignored: true, reported_at: nil)
      create_oom_report_fixture!(vps: reported_vps, ignored: false, reported_at: 1.hour.ago)
      captured_vps_ids = nil
      allow(TransactionChains::Vps::OomReports).to receive(:fire2) do |args:, kwargs:|
        captured_vps_ids = args.first.map(&:id)
        expect(kwargs).to include(:cooldown)
      end

      task.notify

      expect(captured_vps_ids).to eq([selected_vps.id])
    end

    it 'passes through cooldown from the environment' do
      create_oom_report_fixture!(vps: create_vps!, reported_at: nil)

      with_env('COOLDOWN' => '42') do
        task.notify
      end

      expect(TransactionChains::Vps::OomReports).to have_received(:fire2).with(
        args: [anything],
        kwargs: { cooldown: 42 }
      )
    end

    it 'does nothing when there is nothing to notify' do
      create_oom_report_fixture!(vps: create_vps!, reported_at: 1.hour.ago)

      task.notify

      expect(TransactionChains::Vps::OomReports).not_to have_received(:fire2)
    end
  end

  describe '#prune' do
    it 'deletes old reports in batches and prints a summary count' do
      old_reports = 2.times.map do |i|
        create_oom_report_fixture!(vps: create_vps!, created_at: (i + 2).days.ago)
      end
      fresh = create_oom_report_fixture!(vps: create_vps!, created_at: 1.hour.ago)

      expect do
        with_env('DAYS' => '1') do
          task.prune
        end
      end.to output("Deleted 2 OOM reports\n").to_stdout

      expect(OomReport.where(id: old_reports.map(&:id))).to be_empty
      expect(OomReport.find_by(id: fresh.id)).to be_present
    end
  end
end
