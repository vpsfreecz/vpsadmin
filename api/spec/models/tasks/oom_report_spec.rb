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
