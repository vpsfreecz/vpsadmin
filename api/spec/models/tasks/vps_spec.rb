# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Vps do
  let(:task) { described_class.new }

  it 'prunes only VPS status logs older than the configured number of days' do
    stub_const("#{described_class}::DAYS", 1)
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    old = VpsStatus.create!(vps: vps, status: true, is_running: true, created_at: 2.days.ago)
    recent = VpsStatus.create!(vps: vps, status: true, is_running: false, created_at: 12.hours.ago)

    expect { task.prune_status_logs }.to output("Deleted 1 VPS status logs\n").to_stdout

    expect(VpsStatus.find_by(id: old.id)).to be_nil
    expect(VpsStatus.find_by(id: recent.id)).to be_present
  end
end
