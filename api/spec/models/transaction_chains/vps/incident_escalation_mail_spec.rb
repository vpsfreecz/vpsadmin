require 'spec_helper'

RSpec.describe TransactionChains::Vps::IncidentEscalationMail do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:action) do
    incident = IncidentReport.create!(vps:, user: vps.user, codename: 'oomd', subject: 'Test', text: 'Test', detected_at: Time.utc(2026, 1, 10, 12))
    VpsIncidentAction.create!(vps:, user: vps.user, incident_report: incident, incident_type: 'oomd', kind: 'warning',
                              incident_count_7d: 5, incident_count_30d: 5)
  end
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }

  before do
    ensure_alert_mail_templates!
    ensure_mailer_available!
  end

  it 'renders current limits and exemption with historical counts after a manual start' do
    ensure_alert_mail_templates!
    ensure_mailer_available!
    vps = build_standalone_vps_fixture.fetch(:vps)
    incident = IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'OOM', text: 'OOM', detected_at: Time.now,
                                      source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
    action = VpsIncidentAction.create!(vps:, user: vps.user, incident_report: incident, incident_type: 'oomd', kind: 'stop', state: 'completed',
                                       completed_at: Time.now, incident_count_7d: 5, incident_count_30d: 10)
    # A normal start confirms autostart=true before this notification is queued.
    vps.update!(autostart_enable: true)
    IncidentEscalation.update_settings!(vps, incident_policy: 'oomd', incident_enforcement_enabled: false, incident_stop_limit_override: 20)
    described_class.fire(action)
    text = action.reload.mail_log.text_plain
    expect(text).to include('The automatic stop also disabled autostart.', 'stop limit: 20')
    expect(text).not_to include('Autostart is disabled.', 'it will be stopped again')
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
    expect(vps.vps_incident_policies.find_by(incident_type: 'oomd')&.last_warning_at).to be_nil
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
    expect(text).to include('Incident type: VPS memory-pressure incidents', 'CET')
    expect(text).not_to include('Incidenty přetížení paměti VPS')
  end

  it 'renders the Czech label when the selected template has a Czech translation' do
    translation = specific.mail_template_translations.first
    specific.mail_template_translations.create!(language: Language.find_by!(code: 'cs'), from: translation.from,
                                                subject: 'Typ: <%= @incident_type_label %>', text_plain: 'Typ: <%= @incident_type_label %>')
    vps.user.update!(language: Language.find_by!(code: 'cs'))
    described_class.fire(action)
    expect(action.reload.mail_log.subject).to eq('Typ: Incidenty přetížení paměti VPS')
  end
end
