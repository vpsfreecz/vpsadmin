# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'outage reports plugin rake tasks', requires_plugins: :outage_reports do # rubocop:disable RSpec/DescribeClass
  include OutageReportsSpecHelpers

  around do |example|
    with_rake_application do
      load_plugin_rake_tasks('plugins/outage_reports/api/tasks/outage_reports.rake')
      with_current_context(user: SpecSeed.admin) { example.run }
    end
  end

  def outage(attrs)
    create_outage_with_translation!({
      outage_type: :maintenance,
      impact_type: :network,
      duration: 30,
      begins_at: 2.hours.ago,
      auto_resolve: true
    }.merge(attrs))
  end

  it 'auto-resolves only eligible announced outages' do
    finished = outage(state: :announced, finished_at: 1.minute.ago)
    elapsed = outage(state: :announced, begins_at: 2.hours.ago, finished_at: nil, duration: 15)
    2.times do
      OutageUpdate.create!(outage: elapsed, reported_by: SpecSeed.admin, state: :announced)
    end
    too_many_updates = outage(state: :announced, begins_at: 2.hours.ago, finished_at: nil, duration: 15)
    3.times do
      OutageUpdate.create!(outage: too_many_updates, reported_by: SpecSeed.admin, state: :announced)
    end
    auto_disabled = outage(state: :announced, finished_at: 1.minute.ago, auto_resolve: false)
    resolved = outage(state: :resolved, finished_at: 1.minute.ago)
    cancelled = outage(state: :cancelled, finished_at: 1.minute.ago)

    invoke_rake_task(
      'vpsadmin:outage_reports:auto_resolve',
      env: { MIN_DURATION: '900', DELAY: '600' }
    )

    expect([finished.reload.state, elapsed.reload.state]).to contain_exactly('resolved', 'resolved')
    expect(
      [
        too_many_updates.reload.state,
        auto_disabled.reload.state,
        resolved.reload.state,
        cancelled.reload.state
      ]
    ).to eq(%w[announced announced resolved cancelled])
  end
end
