# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::IncidentReport do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  before do
    allow(TransactionChains::IncidentReport::Process).to receive(:fire)
    allow(VpsAdmin::API::NotificationEvents).to receive(:run_chain)
  end

  def create_unreported_incident!(**attrs)
    ret = create_incident_report_fixture!(reported_at: nil, **attrs)
    ret.is_a?(Hash) ? ret.fetch(:incident) : ret
  end

  it 'does nothing when there are no unreported incidents' do
    create_incident_report_fixture!

    task.process

    expect(TransactionChains::IncidentReport::Process).not_to have_received(:fire)
    expect(VpsAdmin::API::NotificationEvents).not_to have_received(:run_chain)
  end

  it 'releases all direct-only incidents without a transaction chain' do
    incidents = [
      create_unreported_incident!(subject: 'Incident A'),
      create_unreported_incident!(subject: 'Incident B')
    ]

    task.process

    expect(VpsAdmin::API::NotificationEvents).to have_received(:run_chain).with(
      TransactionChains::IncidentReport::Process,
      args: [match_array(incidents)]
    )
    expect(TransactionChains::IncidentReport::Process).not_to have_received(:fire)
  end

  it 'uses a transaction chain only for incidents with side effects' do
    cpu_limit = create_unreported_incident!(subject: 'Incident A', cpu_limit: 50)
    stop = create_unreported_incident!(subject: 'Incident B', vps_action: 'stop')
    direct = create_unreported_incident!(subject: 'Incident C')
    processed = []
    allow(TransactionChains::IncidentReport::Process).to receive(:fire) do |batch|
      processed << batch.map(&:id)
    end

    task.process

    expect(VpsAdmin::API::NotificationEvents).to have_received(:run_chain).with(
      TransactionChains::IncidentReport::Process,
      args: [[direct]]
    )
    expect(processed).to contain_exactly([cpu_limit.id], [stop.id])
  end

  it 'warns and continues when one incident is locked' do
    locked = create_unreported_incident!(subject: 'Locked incident', cpu_limit: 50)
    other = create_unreported_incident!(subject: 'Other incident')
    processed = []
    allow(TransactionChains::IncidentReport::Process).to receive(:fire) do |batch|
      raise ResourceLocked.new(batch.first.vps, 'locked') if batch.first.id == locked.id

      processed << batch.first.id
    end

    expect do
      task.process
    end.to output(/Unable to process incident ##{locked.id}: VPS #{locked.vps.id} is locked/).to_stderr
    expect(processed).to be_empty
    expect(VpsAdmin::API::NotificationEvents).to have_received(:run_chain).with(
      TransactionChains::IncidentReport::Process,
      args: [[other]]
    )
  end
end
