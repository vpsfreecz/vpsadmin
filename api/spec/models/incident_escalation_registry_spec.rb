require 'spec_helper'

RSpec.describe IncidentEscalation do
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }
  let(:now) { Time.now.utc.change(usec: 0) }
  let(:other) do
    described_class::Rule.new(key: 'spec_other', labels: { 'en' => 'Test incidents', 'cs' => 'Zkušební incidenty' },
                              category: 'incident_policy_test', qualification: ->(scope) { scope.where(codename: 'spec_other') })
  end

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    stub_const('IncidentEscalation::RULES', described_class::RULES.merge(other.key => other))
    SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update!(value: 'enforce')
    SysConfig.create!(category: other.category, name: 'mode', value: 'enforce', data_type: 'String')
    ensure_alert_mail_templates!
    ensure_mailer_available!
  end

  def report(type, time = now)
    IncidentReport.create!(vps:, user: vps.user, codename: type, subject: 'Test incident', text: 'Test incident', detected_at: time,
                           source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
  end

  def arrive(type, time = now)
    described_class.ingest!(vps, incident_type: type, now:, attributes: {
                             codename: type, subject: 'Manual test source', text: 'Explicitly qualified test source', detected_at: time
                           })
  end

  it 'qualifies backend provenance and preserves historical source after migration' do
    qualified = report('oomd')
    report('oomd').update!(source_kind: nil)
    report('oomd').update!(source_node_id: nil)
    report('oomd').update!(source_action: 'kill')
    report('lookalike')
    report('oomd').update!(source_key: nil)
    expect(described_class.rule.reports.where(vps:).pluck(:id)).to eq([qualified.id])
    vps.update!(node: SpecSeed.other_node)
    expect(described_class.new(vps, now:).counts).to eq([1, 1])
  end

  it 'evaluates the selected registered type at arrival, without a node source key' do
    vps.update!(incident_enforcement_enabled: false)
    vps.vps_incident_policies.create!(incident_type: other.key, warning_limit_override: 2)
    4.times { report('oomd', now - 1) }
    arrive(other.key, now - 1)
    expect(vps.vps_incident_actions).to be_empty
    arrive(other.key)
    action = vps.vps_incident_actions.sole
    expect(action).to have_attributes(incident_type: other.key, kind: 'warning', incident_count_7d: 2, mail_state: 'queued')
    expect(action.mail_log.mail_template.name).to eq('vps_incident_warning')
    expect(vps.vps_incident_policies.find_by!(incident_type: other.key).last_warning_at).to eq(now)
    expect(vps.vps_incident_policies.find_by(incident_type: 'oomd')).to be_nil
    VpsIncidentSummary.load([vps], incident_type: other.key, now:, language: :cs)
    expect(vps.incident_summary).to include(incident_count_7d: 2, incident_warning_limit: 2, incident_policy_label: 'Zkušební incidenty')
    VpsIncidentSummary.load([vps], incident_type: 'oomd', now:)
    expect(vps.incident_summary).to include(incident_count_7d: 4, incident_warning_limit: 5, incident_last_warning_at: nil)
  end

  it 'shares physical stop exclusion, cooldown and exemption across selected rules' do
    9.times { report(other.key, now - 1) }
    arrive(other.key)
    action = vps.vps_incident_actions.sole
    expect(action).to have_attributes(kind: 'stop', state: 'queued', incident_type: other.key)
    10.times { report('oomd', now - 1) }
    VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(vps, node: vps.node, action: 'restart', time: now, now:)
    expect(vps.vps_incident_actions.where(kind: 'stop').count).to eq(1)
    VpsIncidentSummary.load([vps], now:)
    expect(vps.incident_summary).to include(incident_action_state: 'pending', incident_action_chain_id: action.transaction_chain_id)
    action.update!(state: 'completed', mail_state: 'sent')
    vps.update!(incident_last_stop_at: now - 60, incident_enforcement_enabled: false)
    arrive(other.key)
    expect(vps.vps_incident_actions.where(kind: 'stop').count).to eq(1)
    vps.update!(incident_enforcement_enabled: true)
    arrive(other.key)
    expect(vps.vps_incident_actions.where(kind: 'stop').count).to eq(1)
    VpsIncidentSummary.load([vps], incident_type: other.key, now:)
    expect(vps.incident_summary[:incident_next_stop_allowed_at]).to eq(now - 60 + described_class::DAY)
  end

  it 'does not enroll unknown codenames or permit unknown registered keys' do
    expect { arrive('unregistered') }.to raise_error(ArgumentError, 'Invalid incident policy')
    expect(IncidentReport.where(codename: 'unregistered')).to be_empty
    expect(IncidentEscalation::RULES.keys).to contain_exactly('oomd', 'spec_other')
  end

  it 'resets every type warning at confirmed ownership transfer and retains the shared stop' do
    %w[oomd spec_other].each do |type|
      vps.vps_incident_policies.create!(incident_type: type, last_warning_at: now - 10)
    end
    vps.update!(incident_last_stop_at: now - 20)
    chain = TransactionChains::Vps::Update.create!(name: 'update', state: :done, user: SpecSeed.admin, size: 1)
    transaction = Transaction.create!(transaction_chain: chain, handle: 3041, node: vps.node, queue: 'vps')
    transaction.update_columns(done: 1, status: 1, finished_at: now)
    vps.update_columns(incident_owner_transfer_chain_id: chain.id)
    described_class.new(vps, now:).reconcile_transfer!
    expect(vps.vps_incident_policies.pluck(:last_warning_at)).to all(be_nil)
    expect(vps).to have_attributes(incident_accounting_since: now, incident_last_stop_at: now - 20)
    [other.key, 'oomd'].each { |type| expect(described_class.new(vps, incident_type: type, now:).counts).to eq([0, 0]) }
  end
end
