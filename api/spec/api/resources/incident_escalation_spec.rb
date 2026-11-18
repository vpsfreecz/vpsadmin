require 'spec_helper'

RSpec.describe VpsAdmin::API::Resources::VPS do
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }
  let(:now) { Time.now.utc.change(usec: 0) }

  before do
    install_incident_policy_fixture
    header 'Accept', 'application/json'
  end

  def policy_path(key = nil)
    vpath("/vpses/#{vps.id}/incident_policies#{"/#{key}" if key}")
  end

  def update_policy(values)
    put policy_path('oomd'), JSON.dump(incident_policy: values), 'CONTENT_TYPE' => 'application/json'
  end

  def member(time = now)
    IncidentReport.create!(vps:, user: vps.user, subject: 'Source', text: 'Source', codename: 'oomd',
                           detected_at: time, source_key: SecureRandom.hex(32), source_kind: 'node_vps_event',
                           source_action: 'restart', source_node_id: vps.node_id)
  end

  it 'declares generic typed resources in the actual API description' do
    scopes = EndpointInventory.scopes_for_version(self, api_version)
    expect(scopes).to include('incident_policy#index', 'incident_policy#show', 'vps.incident_policy#index',
                              'vps.incident_policy#show', 'vps.incident_policy#update', 'incident_report.policy_evaluation#index')
  end

  it 'discovers all declarations and returns known limits without overrides or matches, hiding admin settings' do
    as(vps.user) { get vpath('/incident_policies') }
    expect(json['status']).to be(true), json.inspect
    metadata = json.fetch('response').fetch('incident_policies').sole
    expect(metadata).to include('key' => 'oomd', 'warning_period_days' => 7)
    expect(metadata.keys).not_to include('settings_category', 'source_type')
    as(vps.user) { get vpath('/incident_policies/oomd') }
    expect(json['status']).to be(true), json.inspect
    expect(json.fetch('response').fetch('incident_policy')).to eq(metadata.except('_meta'))
    as(vps.user) { get policy_path }
    expect(json['status']).to be(true), json.inspect
    row = json.fetch('response').fetch('incident_policies').sole
    expect(row).to include('key' => 'oomd', 'count_7d' => 0, 'count_30d' => 0, 'configuration_valid' => true,
                           'warning_limit' => 5, 'stop_limit' => 10, 'status' => 'clear', 'evaluation_state' => 'none')
    expect(row.keys).not_to include('warning_limit_override', 'stop_limit_override', 'settings_category')
    as(SpecSeed.admin) { get policy_path('oomd') }
    expect(json['status']).to be(true), json.inspect
    expect(json.fetch('response').fetch('incident_policy')).to include('settings_category' => 'incident_policy_oomd',
                                                                       'warning_limit_override' => nil)
  end

  it 'restricts per-VPS readers and rejects member writes and unknown keys' do
    as(SpecSeed.other_user) { get policy_path }
    expect(last_response.status).to eq(404)
    as(vps.user) { update_policy(warning_limit_override: 2) }
    expect(vps.vps_incident_policies).to be_empty
    as(SpecSeed.admin) { get policy_path('not_registered') }
    expect(json['status']).to be(false)
  end

  it 'updates only two audited overrides atomically, preserving omission and explicit null resets' do
    unlock_transaction_signer!
    as(SpecSeed.admin) { update_policy(warning_limit_override: 3, stop_limit_override: 6) }
    expect(json['status']).to be(true), json.inspect
    expect(json.fetch('response').fetch('incident_policy')).to include('warning_limit' => 3, 'stop_limit' => 6)
    policy = vps.vps_incident_policies.sole
    audit = PaperTrail::Version.where(item_type: 'VpsIncidentPolicy', item_id: policy.id).count
    as(SpecSeed.admin) { update_policy(warning_limit_override: 4) }
    expect(policy.reload).to have_attributes(warning_limit_override: 4, stop_limit_override: 6)
    expect(PaperTrail::Version.where(item_type: 'VpsIncidentPolicy', item_id: policy.id).count).to eq(audit + 1)
    as(SpecSeed.admin) { update_policy(warning_limit_override: 7) }
    expect(json['status']).to be(false)
    expect(policy.reload.warning_limit_override).to eq(4)
    as(SpecSeed.admin) { update_policy(stop_limit_override: 2_147_483_648) }
    expect(json['status']).to be(false)
    expect(policy.reload.stop_limit_override).to eq(6)
    as(SpecSeed.admin) { update_policy(warning_limit_override: nil, stop_limit_override: nil) }
    expect(json.fetch('response').fetch('incident_policy')).to include('warning_limit' => 5, 'stop_limit' => 10,
                                                                       'warning_limit_override' => nil, 'stop_limit_override' => nil)
    expect(vps.reload.incident_enforcement_enabled).to be(true)
  end

  it 'keeps shared permission independent of selectors and rejects mixed updates' do
    unlock_transaction_signer!
    as(SpecSeed.admin) do
      put vpath("/vpses/#{vps.id}"), JSON.dump(vps: { incident_enforcement_enabled: false }), 'CONTENT_TYPE' => 'application/json'
    end
    expect(json['status']).to be(true), json.inspect
    expect(vps.reload.incident_enforcement_enabled).to be(false)
    as(SpecSeed.admin) do
      put vpath("/vpses/#{vps.id}"), JSON.dump(vps: { incident_enforcement_enabled: true, hostname: 'mixed' }), 'CONTENT_TYPE' => 'application/json'
    end
    expect(json['status']).to be(false)
    expect(vps.reload.incident_enforcement_enabled).to be(false)
    as(vps.user) { get vpath("/vpses/#{vps.id}") }
    expect(json.fetch('response').fetch('vps')).to include('incident_enforcement_enabled' => false, 'incident_warning_count' => 0,
                                                           'incident_stop_threshold_count' => 0, 'incident_action_state' => 'none')
    expect(json.fetch('response').fetch('vps').keys).not_to include('incident_policy', 'incident_count_7d', 'incident_warning_limit')
  end

  it 'filters reached thresholds before pagination with an explicit key and matches returned aggregate counts' do
    5.times { |i| member(now - i) }
    as(vps.user) { get vpath('/vpses'), vps: { incident_policy: 'oomd', incident_status: 'warning' }, _meta: { count: true } }
    expect(json['status']).to be(true), json.inspect
    expect(json.fetch('response').fetch('vpses').find { |r| r['id'] == vps.id }).to include('incident_warning_count' => 1)
    as(vps.user) { get vpath('/vpses'), vps: { incident_status: 'warning' } }
    expect(json['status']).to be(false)
  end

  it 'uses saved membership for distinct history and typed historical projection, retaining retired keys and privacy' do
    report = member
    source = report.incident_policy_evaluations.sole
    other = source.dup
    other.policy_key = 'retired'
    other.save!
    as(vps.user) { get vpath('/incident_reports'), incident_report: { vps: vps.id, policy_key: 'retired' }, _meta: { count: true } }
    expect(json['status']).to be(true), json.inspect
    expect(json.fetch('response').fetch('incident_reports').map { |r| r['id'] }).to eq([report.id])
    expect(json.dig('response', '_meta', 'total_count')).to eq(1)
    as(vps.user) { get vpath("/incident_reports/#{report.id}/policy_evaluations") }
    expect(json['status']).to be(true), json.inspect
    rows = json.fetch('response').fetch('policy_evaluations')
    expect(rows.map { |r| r['policy_key'] }).to contain_exactly('oomd', 'retired')
    expect(rows.first).to include('count_7d' => 1, 'warning_limit' => 5, 'state' => 'recorded',
                                  'matched' => true, 'warning_period_days' => 7, 'stop_period_days' => 30)
    expect(rows.first.keys).not_to include('context', 'snapshot', 'error_class', 'error_stage')
    as(SpecSeed.other_user) { get vpath("/incident_reports/#{report.id}/policy_evaluations") }
    expect(last_response.status).to eq(404)
    vps.update_columns(incident_accounting_since: now + 1)
    as(vps.user) { get vpath("/incident_reports/#{report.id}/policy_evaluations") }
    expect(last_response.status).to eq(404)
    as(SpecSeed.admin) { get vpath("/incident_reports/#{report.id}/policy_evaluations") }
    expect(json['status']).to be(true)
  end

  it 'creates an ordinary non-OOM API report with both saved policies before one real source mail' do
    install_generic_incident_policy_fixture
    unlock_transaction_signer!
    ensure_alert_mail_templates!
    ensure_mailer_available!
    template = MailTemplate.find_by!(name: 'vps_incident_report')
    expect do
      as(SpecSeed.admin) do
        post vpath('/incident_reports'), JSON.dump(incident_report: {
          vps: vps.id, codename: 'manual_abuse', subject: 'Manual report', text: 'Report evidence'
        }), 'CONTENT_TYPE' => 'application/json'
      end
    end.to change { MailLog.where(mail_template: template).count }.by(1)
    expect(json['status']).to be(true), json.inspect
    report = IncidentReport.find_by!(vps:, subject: 'Manual report')
    expect(report.incident_policy_evaluations.pluck(:policy_key, :matched)).to contain_exactly(['category', true], ['content', true])
    expect(VpsAdmin::API::IncidentReports.mail_policies(report).map { |row| row.slice(:key, :count_7d, :count_30d) }).to eq([
                                                                                                                              { key: 'category', count_7d: 1, count_30d: 1 }, { key: 'content', count_7d: 1, count_30d: 1 }
                                                                                                                            ])
    expect(MailLog.where(mail_template: template).sole.text_plain).to include('Category policy', 'Content policy', report.text)
    expect(vps.vps_incident_actions).to be_empty
  end

  it 'keeps false, unknown and failed evaluations as admin diagnostics with their saved nullable membership' do
    report = member
    original = report.incident_policy_evaluations.sole
    [['audit', true, 'audit_only'], ['false', false, 'skipped'], ['unknown', nil, 'error'],
     ['invalid', true, 'error'], ['legacy', nil, 'audit_only']].each do |key, matched, state|
      original.dup.tap do |row|
        row.assign_attributes(policy_key: key, matched:, state:)
        row.save!
      end
    end
    as(vps.user) { get vpath("/incident_reports/#{report.id}/policy_evaluations") }
    expect(json.fetch('response').fetch('policy_evaluations').map { |row| row.fetch('policy_key') }).to eq(%w[audit oomd])
    as(SpecSeed.admin) { get vpath("/incident_reports/#{report.id}/policy_evaluations") }
    rows = json.fetch('response').fetch('policy_evaluations').index_by { |row| row.fetch('policy_key') }
    expect(rows.transform_values { |row| row.fetch('matched') }).to eq(
      'oomd' => true, 'audit' => true, 'false' => false, 'unknown' => nil, 'invalid' => true, 'legacy' => nil
    )
    expect(rows.values).to all(include('warning_period_days' => 7, 'stop_period_days' => 30))
  end

  it 'projects a retired notice origin from internally consistent saved linkage for authorized historical access' do
    report = member
    evaluation = report.incident_policy_evaluations.sole
    notice = IncidentReport.create!(vps:, user: vps.user, source_kind: 'incident_policy_notice',
                                    subject: 'Notice', text: 'Notice', detected_at: now)
    action = VpsIncidentAction.create!(vps:, user: vps.user, incident_report: report, incident_policy_evaluation: evaluation,
                                       policy_key: 'oomd', kind: 'warning', incident_count_7d: 1, incident_count_30d: 1,
                                       notice_incident_report: notice)
    stub_const('IncidentEscalation::RULES', {})
    vps.update_columns(user_id: SpecSeed.other_user.id)
    as(SpecSeed.admin) { get vpath("/incident_reports/#{notice.id}") }
    expect(json.fetch('response').fetch('incident_report')).to include(
      'notice_policy_key' => 'oomd', 'notice_policy_label' => evaluation.label('en')
    )
    expect(notice.incident_policy_evaluations).to be_empty
    action.update!(user: SpecSeed.other_user)
    as(SpecSeed.admin) { get vpath("/incident_reports/#{notice.id}") }
    expect(json.fetch('response').fetch('incident_report')).to include('notice_policy_key' => nil, 'notice_policy_label' => nil)
    as(SpecSeed.admin) { get vpath("/incident_reports/#{report.id}") }
    expect(json.fetch('response').fetch('incident_report')).to include('notice_policy_key' => nil, 'notice_policy_label' => nil)
  end
end
