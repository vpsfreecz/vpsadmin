require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::Rpc::Handler do
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }
  let(:handler) { described_class.new(vps.node) }
  let(:facts) do
    { request_token: SecureRandom.uuid, vps_id: vps.id, subject: 'Manual category', text: 'Operator evidence',
      detected_at: Time.now.utc.iso8601, codename: 'manual_abuse', cpu_limit: nil,
      vps_action: 'none', filed_by_id: SpecSeed.admin.id }
  end

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    allow(TransactionChains::IncidentReport::New).to receive(:fire).and_return([nil, nil])
  end

  it 'is allowlisted and deduplicates the exact report and source notification using the retained token' do
    install_generic_incident_policy_fixture
    expect(described_class::COMMANDS).to include('create_incident_report')
    first = handler.create_incident_report(**facts)
    expect(handler.create_incident_report(**facts)).to eq(first)
    report = IncidentReport.find(first.fetch(:id))
    expect(report).to have_attributes(user_id: vps.user_id, vps_id: vps.id, source_kind: 'node_incident_report',
                                      source_node_id: vps.node_id, source_action: nil, filed_by_id: SpecSeed.admin.id)
    expect(report.source_key).to match(/\A[0-9a-f]{64}\z/)
    expect(report.notification_processed_at).to be_present
    expect(TransactionChains::IncidentReport::New).to have_received(:fire).once
    expect(report.incident_policy_evaluations.pluck(:policy_key, :matched)).to contain_exactly(['category', true], ['content', true])
  end

  it 'preserves CPU limit and explicit action inputs for the normal chain without an automatic policy action' do
    install_generic_incident_policy_fixture(mode: 'enforce')
    report = IncidentReport.find(handler.create_incident_report(**facts, cpu_limit: 25, vps_action: 'suspend').fetch(:id))
    expect(report).to have_attributes(cpu_limit: 25, vps_action: 'suspend', filed_by_id: SpecSeed.admin.id)
    expect(TransactionChains::IncidentReport::New).to have_received(:fire).with(report).once
    expect(report.incident_policy_evaluations.pluck(:matched)).to eq([true, true])
    expect(report.incident_policy_evaluations.map { |e| e.snapshot.fetch('decision') }).to eq(%w[none none])
    expect(vps.vps_incident_actions).to be_empty
  end

  it 'rejects a foreign VPS, forged provenance or owner and token-content conflicts before another report' do
    foreign = described_class.new(SpecSeed.other_node)
    expect { foreign.create_incident_report(**facts) }.to raise_error(ActiveRecord::RecordNotFound)
    %i[user_id source_kind source_node_id source_key].each do |key|
      expect { handler.create_incident_report(**facts, key => 'forged') }.to raise_error(ArgumentError)
    end
    handler.create_incident_report(**facts)
    expect { handler.create_incident_report(**facts, text: 'Different evidence') }
      .to raise_error(ArgumentError, /token was reused/)
    expect(IncidentReport.where(vps: vps).count).to eq(1)
  end

  it 'rolls creation and policy outcomes back when normal explicit-chain preparation fails' do
    install_incident_policy_fixture
    allow(TransactionChains::IncidentReport::New).to receive(:fire).and_raise(ResourceLocked.new(vps, 'busy'))
    expect { handler.create_incident_report(**facts, vps_action: 'stop') }.to raise_error(ResourceLocked)
    expect(IncidentReport.where(vps:)).to be_empty
    expect(IncidentPolicyEvaluation.count).to eq(0)
    allow(TransactionChains::IncidentReport::New).to receive(:fire).and_return([nil, nil])
    report = IncidentReport.find(handler.create_incident_report(**facts).fetch(:id))
    expect(report.incident_policy_evaluations.sole.matched).to be(false)
  end
end
