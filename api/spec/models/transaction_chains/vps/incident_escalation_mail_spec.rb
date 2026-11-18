require 'spec_helper'

RSpec.describe TransactionChains::Vps::IncidentEscalationMail do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:action) do
    incident = IncidentReport.create!(vps:, user: vps.user, codename: 'oomd', subject: 'Test', text: 'Test', detected_at: Time.utc(2026, 1, 10, 12),
                                      source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
    evaluation = incident.incident_policy_evaluations.sole
    VpsIncidentAction.create!(vps:, user: vps.user, incident_report: incident, policy_key: 'oomd', incident_policy_evaluation: evaluation,
                              kind: 'warning', incident_count_7d: 5, incident_count_30d: 5)
  end
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }

  before do
    install_incident_policy_fixture
    ensure_alert_mail_templates!
    ensure_mailer_available!
  end

  it 'renders current limits and exemption with historical counts after a manual start' do
    ensure_alert_mail_templates!
    ensure_mailer_available!
    vps = build_standalone_vps_fixture.fetch(:vps)
    incident = IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'OOM', text: 'OOM', detected_at: Time.now,
                                      source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
    evaluation = incident.incident_policy_evaluations.sole
    action = VpsIncidentAction.create!(vps:, user: vps.user, incident_report: incident, policy_key: 'oomd', incident_policy_evaluation: evaluation,
                                       kind: 'stop', state: 'completed',
                                       completed_at: Time.now, incident_count_7d: 5, incident_count_30d: 10)
    # A normal start confirms autostart=true before this notification is queued.
    vps.update!(autostart_enable: true)
    IncidentEscalation.update_policy!(vps, 'oomd', stop_limit_override: 20)
    IncidentEscalation.update_settings!(vps, incident_enforcement_enabled: false)
    described_class.fire(action)
    text = action.reload.mail_log.text_plain
    expect(text).to include('30 days | 10 | 20 | VPS stop')
    expect(text).not_to include('autostart', 'it will be stopped again', 'may be stopped again')
    expect(vps.reload.autostart_enable).to be(true)
  end

  def specific
    MailTemplate.find_by!(name: 'vps_memory_pressure_warning')
  end

  it 'uses the generic template only when the registered specific definition is absent' do
    specific.destroy!
    described_class.fire(action)
    expect(action.reload.mail_log.mail_template.name).to eq('vps_incident_warning')
    expect(action.mail_log.message_id).to eq("<vps-incident-action-#{action.id}@vpsadmin>")
  end

  it 'suppresses disabled specific mail without selecting generic or advancing warning time' do
    UserMailTemplateRecipient.handle_update!(vps.user, specific, enabled: false)
    expect { described_class.fire(action) }.not_to change(MailLog, :count)
    expect(action.reload).to have_attributes(state: 'completed', mail_state: 'suppressed', mail_log_id: nil)
    expect(vps.vps_incident_policies.find_by(policy_key: 'oomd')&.last_warning_at).to be_nil
  end

  it 'keeps rendering and translation errors on the selected specific identity' do
    specific.mail_template_translations.update_all(text_plain: '<%= raise "specific failed" %>')
    expect { described_class.fire(action) }.to raise_error(RuntimeError, 'specific failed')
    expect(MailLog.where(mail_template: MailTemplate.find_by!(name: 'vps_incident_warning'))).to be_empty
    specific.mail_template_translations.delete_all
    expect { described_class.fire(action) }.to raise_error(VpsAdmin::API::Exceptions::MailTemplateDoesNotExist)
  end

  it 'uses the actual EN fallback label and recipient timezone for a Czech user' do
    vps.user.update!(language: Language.find_by!(code: 'cs'), time_zone: 'Europe/Prague')
    described_class.fire(action)
    text = action.reload.mail_log.text_plain
    expect(text).to include('CET')
    expect(text).not_to include('Incidenty přetížení paměti VPS')
    vars = IncidentEscalation.new(vps, policy_key: 'oomd').mail_vars(action, language: 'en')
    expect(vars[:incident_type_label]).to eq('VPS memory-pressure incidents')
  end

  it 'renders the Czech label when the selected template has a Czech translation' do
    translation = specific.mail_template_translations.first
    specific.mail_template_translations.create!(language: Language.find_by!(code: 'cs'), from: translation.from,
                                                subject: 'Typ: <%= @incident_type_label %>', text_plain: 'Typ: <%= @incident_type_label %>')
    vps.user.update!(language: Language.find_by!(code: 'cs'))
    described_class.fire(action)
    expect(action.reload.mail_log.subject).to eq('Typ: Incidenty přetížení paměti VPS')
  end

  it 'retains saved policy labels and selected template identities after declaration edits or removal' do
    original = action
    vps.user.update!(language: Language.find_by!(code: 'cs'))
    saved = original.saved_policy_evaluation.deep_dup
    changed = IncidentEscalation.rule('oomd').dup
    changed.labels = { 'en' => 'Changed label', 'cs' => 'Nový název' }
    changed.warning_template = :vps_incident_warning
    stub_const('IncidentEscalation::RULES', { 'oomd' => changed }.freeze)
    described_class.fire(original)
    expect(original.reload.mail_log.mail_template.name).to eq('vps_memory_pressure_warning')
    expect(original.mail_log.text_plain).not_to include('Changed label', 'Nový název')
    expect(original.saved_policy_evaluation).to eq(saved)

    stub_const('IncidentEscalation::RULES', {}.freeze)
    described_class.fire(original)
    expect(original.reload.mail_log.mail_template.name).to eq('vps_memory_pressure_warning')
    language = MailTemplate.mail_template_translation_for(specific, vps.user.language).language.code
    expect(original.mail_log.text_plain).to include(saved.fetch('metadata').fetch('labels').fetch(language))
    expect(original.saved_policy_evaluation).to eq(saved)
  end

  it 'identifies notices and generic aggregate mail from saved metadata for arbitrary policies' do
    original = action
    saved = original.saved_policy_evaluation.deep_dup
    saved['metadata'].merge!('key' => 'arbitrary', 'labels' => { 'en' => 'Saved <policy>', 'cs' => 'Uložené <pravidlo>' },
                             'warning_template' => 'vps_incident_warning', 'stopped_template' => 'vps_incident_stopped')
    IncidentPolicyEvaluation.where(id: original.incident_policy_evaluation_id).update_all(policy_key: 'arbitrary', snapshot: saved)
    original.update!(policy_key: 'arbitrary')
    original.reload
    stub_const('IncidentEscalation::RULES', {}.freeze)
    described_class.fire(original)
    expect(original.reload.mail_log.mail_template.name).to eq('vps_incident_warning')
    expect(original.mail_log.subject).to include('Saved <policy>')
    expect(original.mail_log.text_plain).to include('Saved <policy>')
    expect(original.mail_log.text_html).to include('Saved &lt;policy&gt;')
    expect(original.mail_log.text_html).not_to include('Saved <policy>')
    second_snapshot = saved.deep_dup
    second_snapshot['metadata'].merge!('key' => 'zeta', 'labels' => { 'en' => 'Zeta policy' })
    second_evaluation = original.incident_report.incident_policy_evaluations.create!(
      policy_key: 'zeta', matched: true, state: 'recorded', evaluated_at: original.incident_policy_evaluation.evaluated_at,
      snapshot: second_snapshot
    )
    second = VpsIncidentAction.create!(vps:, user: vps.user, incident_report: original.incident_report, policy_key: 'zeta',
                                       incident_policy_evaluation: second_evaluation, kind: 'warning', incident_count_7d: 6, incident_count_30d: 8)
    described_class.fire(second)
    expect(second.reload.mail_log.subject).to include('Zeta policy')
    expect(second.mail_log.text_plain).to include('Zeta policy', '30 days | 8 | 10 | VPS stop')
    expect(second.mail_log.text_plain).not_to include('Saved <policy>')
    expect(second.mail_log.message_id).not_to eq(original.mail_log.message_id)
    %w[en cs].each do |code|
      vps.user.update!(language: Language.find_by!(code:))
      original.reload
      message = VpsAdmin::API::IncidentReports.escalation_message(original)
      expect(message[:subject]).to include(saved.fetch('metadata').fetch('labels').fetch(code))
      expect(message[:text]).to start_with("#{saved.fetch('metadata').fetch('labels').fetch(code)}\n\n")
    end
  end

  context 'with the actual contributor producer and selected templates' do
    before do
      if ENV['VPSADMIN_SPEC_MAIL_TEMPLATES']
        VpsAdmin::API::MailTemplates.reconcile!(path: ENV.fetch('VPSADMIN_SPEC_MAIL_TEMPLATES'), source_id: 'spec-runtime-policy')
      end
      SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update!(value: 'enforce')
    end

    def decision(count)
      now = Time.now.utc.change(usec: 0)
      mode = SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode')
      reports = travel_to(now) do
        mode.update!(value: 'observe')
        older = Array.new(count - 1) do |index|
          IncidentReport.create!(vps:, user: vps.user, codename: 'oomd', subject: "Source #{index + 1} <plain>", text: 'Not included in evidence mail',
                                 detected_at: now - index - 1, source_key: SecureRandom.hex(32), source_kind: 'node_vps_event',
                                 source_action: 'restart', source_node_id: vps.node_id)
        end
        mode.update!(value: 'enforce')
        trigger = IncidentReport.create!(vps:, user: vps.user, codename: 'oomd', subject: 'Source 0 <plain>', text: 'Not included in evidence mail',
                                         detected_at: now, source_key: SecureRandom.hex(32), source_kind: 'node_vps_event',
                                         source_action: 'restart', source_node_id: vps.node_id)
        [trigger, *older]
      end
      [vps.vps_incident_actions.sole, reports, now]
    end

    it 'renders only available selected reports with truthful visible counts and actual language/timezone' do
      action, reports, = decision(7)
      vps.user.update!(language: Language.find_by!(code: 'cs'), time_zone: 'Europe/Prague')
      reports[1].destroy!
      actual_language = specific.mail_template_translations.exists?(language: Language.find_by!(code: 'cs')) ? :cs : :en
      vars = IncidentEscalation.new(vps, policy_key: 'oomd').mail_vars(action, language: actual_language)
      expect(vars).to include(contributing_incident_shown: 5, contributing_incident_count: 7, contributing_incident_omitted: 2,
                              incident_type_label: IncidentEscalation.rule('oomd').label(actual_language))
      described_class.fire(action)
      mail = action.reload.mail_log
      text = mail.text_plain
      expected_time = reports.first.detected_at.in_time_zone('Europe/Prague').strftime('%Y-%m-%d %H:%M:%S %Z')
      visible = reports.take(5).reject { |report| report.id == reports[1].id }
      expect(text.scan(/^\s+#(\d+)/).flatten.map(&:to_i)).to eq(visible.map(&:id))
      expect(text).to include(expected_time)
      expect(text).to include(actual_language == :cs ? '7 dní | 7 | 5 | Upozornění' : '7 days | 7 | 5 | Warning')
      expect(text).to include(actual_language == :cs ? 'Incidenty (4/7):' : 'Incidents (4/7):')
      expect(text).not_to include(reports[1].subject, reports[6].subject, 'Not included in evidence mail')
      expect(mail.text_html).to include('Source 0 &lt;plain&gt;')
      expect(mail.text_html).not_to include(reports.first.subject, 'Not included in evidence mail')
      expect(mail.mail_template.name).to eq('vps_memory_pressure_warning')
    end

    it 'keeps the saved base through declaration edits and applies current overrides to delayed mail' do
      action, reports, now = decision(10)
      expect(action.kind).to eq('stop')
      snapshot = action.contributor_snapshot
      action.update!(state: 'completed', completed_at: now + 1, repeated_stop: true)
      IncidentReport.create!(vps:, user: vps.user, codename: 'oomd', subject: 'Later source must not replace evidence', text: 'Later',
                             detected_at: now + 2, source_key: SecureRandom.hex(32), source_kind: 'node_vps_event',
                             source_action: 'restart', source_node_id: vps.node_id)
      changed = IncidentEscalation.rule('oomd').dup
      changed.stop_limit = 20
      changed.selector = ->(_ctx) { raise 'mail and reads must not run selectors' }
      stub_const('IncidentEscalation::RULES', { 'oomd' => changed }.freeze)
      engine = IncidentEscalation.new(vps, policy_key: 'oomd')
      expect(VpsIncidentSummary.policy_rows([vps]).fetch(vps.id).sole).to include(stop_limit: 20)
      expect(engine.mail_vars(action)).to include(stop_limit: 10)
      template = MailTemplate.find_by!(name: 'vps_memory_pressure_stopped')
      translation = MailTemplate.mail_template_translation_for(template, vps.user.language)
      vars = engine.mail_vars(action, language: translation.language.code)
      body = MailTemplateTranslation::TemplateBuilder.new(vars, time_zone: vps.user.time_zone).build(translation.text_plain)
      expect(body).to include('30 days | 10 | 10 | VPS stop')
      IncidentEscalation.update_policy!(vps, 'oomd', stop_limit_override: 25)
      expect(IncidentEscalation.new(vps, policy_key: 'oomd').mail_vars(action)).to include(stop_limit: 25)
      described_class.fire(action)
      text = action.reload.mail_log.text_plain
      expect(text).to include('30 days | 10 | 25 | VPS stop', reports.first.subject)
      expect(text).not_to include('Later source must not replace evidence')
      expect(action.contributor_snapshot).to eq(snapshot)
    end

    it 'omits missing contributors, timestamps and links without fallback filler or invented counts' do
      action, reports, = decision(5)
      reports.each(&:destroy!)
      action.reload
      base = SysConfig.find_or_initialize_by(category: 'webui', name: 'base_url')
      base.update!(value: '', data_type: 'String')
      described_class.fire(action)
      text = action.reload.mail_log.text_plain
      expect(text).not_to include('unavailable', 'Incidents (', 'Incident history in vpsAdmin:', '1970', 'Showing ', 'page=incidents')
      expect(action.mail_log.text_html).not_to include('unavailable', '<li>', '1970', 'page=incidents')
    end
  end
end
