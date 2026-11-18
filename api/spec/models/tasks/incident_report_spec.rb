# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::IncidentReport do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  before do
    allow(TransactionChains::IncidentReport::Process).to receive(:fire)
  end

  def create_unreported_incident!(**attrs)
    ret = create_incident_report_fixture!(reported_at: nil, **attrs)
    ret.is_a?(Hash) ? ret.fetch(:incident) : ret
  end

  it 'does nothing when there are no unreported incidents' do
    create_incident_report_fixture!

    task.process

    expect(TransactionChains::IncidentReport::Process).not_to have_received(:fire)
  end

  it 'fires one Process chain for all incidents when none has a CPU limit' do
    incidents = [
      create_unreported_incident!(subject: 'Incident A'),
      create_unreported_incident!(subject: 'Incident B')
    ]
    processed = nil
    allow(TransactionChains::IncidentReport::Process).to receive(:fire) do |batch|
      processed = batch
    end

    task.process

    expect(TransactionChains::IncidentReport::Process).to have_received(:fire).once
    expect(processed.map(&:id)).to match_array(incidents.map(&:id))
  end

  it 'processes incidents one by one when any incident has a CPU limit' do
    incidents = [
      create_unreported_incident!(subject: 'Incident A', cpu_limit: 50),
      create_unreported_incident!(subject: 'Incident B')
    ]
    processed = []
    allow(TransactionChains::IncidentReport::Process).to receive(:fire) do |batch|
      processed << batch.map(&:id)
    end

    task.process

    expect(processed).to match_array(incidents.map { |inc| [inc.id] })
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
    expect(processed).to eq([other.id])
  end

  it 'processes saved generic memberships without selecting again or enrolling legacy reports' do
    legacy = create_unreported_incident!(subject: 'Legacy ordinary report')
    install_generic_incident_policy_fixture
    vps = build_standalone_vps_fixture.fetch(:vps)
    report = IncidentReport.create!(user: vps.user, vps:, codename: 'manual_abuse', subject: 'Current ordinary report',
                                    text: 'Imported evidence', detected_at: Time.now)
    saved = report.incident_policy_evaluations.order(:policy_key).map(&:attributes)
    IncidentEscalation::RULES.each_value do |rule|
      allow(rule.selector).to receive(:call).and_call_original
    end
    allow(IncidentEscalation).to receive(:process!).and_call_original
    task.process
    expect(IncidentEscalation).to have_received(:process!).with(have_attributes(id: vps.id)).once
    IncidentEscalation::RULES.each_value { |rule| expect(rule.selector).not_to have_received(:call) }
    expect(report.incident_policy_evaluations.reload.order(:policy_key).map(&:attributes)).to eq(saved)
    expect(legacy.incident_policy_evaluations).to be_empty
    expect(TransactionChains::IncidentReport::Process).to have_received(:fire).with(include(legacy))
  end
end
