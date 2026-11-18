# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::IncidentReport::Send do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    install_incident_policy_fixture
    ensure_alert_mail_templates!
    ensure_mailer_available!
    allow(MailTemplate).to receive_messages(send_mail!: build_mail_log_double, send_custom: build_mail_log_double)
  end

  def create_send_incident!(**attrs)
    fixture = build_standalone_vps_fixture(user: attrs.delete(:user) || SpecSeed.user)
    create_incident_report_fixture!(vps: fixture.fetch(:vps), user: fixture.fetch(:vps).user, **attrs)
  end

  def message
    Mail.new.tap do |mail|
      mail.message_id = '<incident-source@test.invalid>'
      mail.subject = 'Abuse report'
    end
  end

  it 'mails only incidents with active users and active VPSes' do
    active = create_send_incident!(subject: 'Active')
    suspended_user = SpecSeed.create_or_update_user!(
      login: "suspended-#{SecureRandom.hex(4)}",
      level: 1,
      email: 'suspended@test.invalid'
    )
    inactive_user = create_send_incident!(user: suspended_user, subject: 'Inactive user')
    inactive_user.user.update_column(:object_state, User.object_states[:suspended])
    inactive_vps = create_send_incident!(subject: 'Inactive VPS')
    inactive_vps.vps.update_column(:object_state, Vps.object_states[:suspended])

    chain, = described_class.fire2(
      args: [VpsAdmin::API::IncidentReports::Result.new(
        incidents: [active, inactive_user, inactive_vps]
      )]
    )

    expect(tx_classes(chain)).to eq([Transactions::Mail::Send])
    expect(MailTemplate).to have_received(:send_mail!).with(
      :vps_incident_report,
      hash_including(vars: hash_including(incident: active))
    ).once
  end

  it 'uses Reply when a message and reply metadata are provided' do
    incident = create_send_incident!
    result = VpsAdmin::API::IncidentReports::Result.new(
      incidents: [incident],
      reply: {
        from: 'abuse@test.invalid',
        to: ['sender@test.invalid']
      }
    )

    allow(TransactionChains::IncidentReport::Reply).to receive(:use_in).and_call_original

    chain, = described_class.fire2(args: [result], kwargs: { message: })

    expect(TransactionChains::IncidentReport::Reply).to have_received(:use_in)
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(MailTemplate).to have_received(:send_custom)
  end

  it 'allows an empty chain when there is nothing to send' do
    chain, = described_class.fire2(
      args: [VpsAdmin::API::IncidentReports::Result.new(incidents: [])]
    )

    expect(chain).to be_nil
    expect(MailTemplate).not_to have_received(:send_mail!)
  end

  context 'with real ordinary templates and saved policy' do
    before do
      allow(MailTemplate).to receive(:send_mail!).and_call_original
      if ENV['VPSADMIN_SPEC_MAIL_TEMPLATES']
        VpsAdmin::API::MailTemplates.reconcile!(path: ENV.fetch('VPSADMIN_SPEC_MAIL_TEMPLATES'), source_id: 'spec-ordinary-policy')
      end
      SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update!(value: 'enforce')
      SysConfig.find_by!(category: 'incident_policy_oomd', name: 'warning_limit').update!(value: 5)
      SysConfig.find_by!(category: 'incident_policy_oomd', name: 'stop_limit').update!(value: 10)
    end

    def receive_first_report(language: 'en')
      vps = build_standalone_vps_fixture.fetch(:vps)
      vps.user.update!(language: Language.find_by!(code: language), time_zone: 'Europe/Prague')
      vps.update_column(:hostname, 'host<script> & <%= 1 + 1 %>')
      now = Time.utc(2026, 1, 10, 12)
      travel_to(now) do
        VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(vps, node: vps.node, action: 'restart', time: now, now:)
      end
      IncidentReport.find_by!(vps:, source_kind: 'node_vps_event')
    end

    def ordinary_mail(incident)
      MailLog.where(user: incident.user, mail_template: MailTemplate.find_by!(name: 'vps_incident_report')).order(:id).last
    end

    %w[en cs].each do |code|
      it "renders the first ordinary incident's saved counts in #{code} plain/HTML and keeps source facts separate" do
        incident = receive_first_report(language: code)
        mail = ordinary_mail(incident)
        translation = MailTemplate.mail_template_translation_for(mail.mail_template, incident.user.language)
        rendered_cs = translation.language.code == 'cs'

        expect(incident.incident_policy_evaluations.sole.snapshot).to include('state' => 'recorded', 'decision' => 'none')
        expect(incident.text).not_to include('7 days', '7 dní', 'warning limit', 'limit upozornění')
        expect(mail.text_plain).to include(incident.text)
        expect(mail.text_plain).not_to include('Stav k:', 'As of:', '2026-01-10 13:00:00 CET')
        expect(mail.text_plain).to include(rendered_cs ? 'Přehled incidentů:' : 'Incident summary:')
        expect(mail.text_plain).to include(rendered_cs ? '7 dní | 1 | 5 | Upozornění' : '7 days | 1 | 5 | Warning')
        expect(mail.text_plain).to include(rendered_cs ? '30 dní | 1 | 10 | Vypnutí VPS' : '30 days | 1 | 10 | VPS stop')
        expect(mail.text_plain).not_to include('warning limit:', 'limit upozornění:')
        expect(mail.text_html).to include('host&lt;script&gt; &amp; &lt;%= 1 + 1 %&gt;')
        expect(mail.text_html).not_to include('host<script>', 'host<script> & 2')
      end
    end

    it 'uses saved policy after settings changes and leaves an already rendered MailLog unchanged' do
      incident = receive_first_report
      original_report = incident.attributes.deep_dup
      previous_mail = ordinary_mail(incident)
      original_mail = previous_mail.attributes.deep_dup
      SysConfig.find_by!(category: 'incident_policy_oomd', name: 'stop_limit').update!(value: 100)
      SysConfig.find_by!(category: 'incident_policy_oomd', name: 'warning_limit').update!(value: 50)
      SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update!(value: 'observe')
      incident.vps.update_column(:incident_enforcement_enabled, false)
      incident.user.update!(language: Language.find_by!(code: 'cs'))
      allow(IncidentEscalation).to receive(:config).and_raise('ordinary rendering must not query current policy')

      described_class.fire(VpsAdmin::API::IncidentReports::Result.new(incidents: [incident]))

      mail = ordinary_mail(incident)
      expect(mail.id).not_to eq(previous_mail.id)
      expect(VpsAdmin::API::IncidentReports.mail_policies(incident).sole).to include(warning_limit: 5, stop_limit: 10, stop_enforced: true)
      expect(mail.text_plain).to include(incident.text)
      expect(mail.text_plain).to match(/30 (?:days|dní) \| 1 \| 10 \| (?:VPS stop|Vypnutí VPS)/)
      expect(mail.text_plain).not_to include('| 100 |', '| 50 |', 'warning limit:', 'limit upozornění:')
      expect(previous_mail.reload.attributes).to eq(original_mail)
      expect(incident.reload.attributes).to eq(original_report)
    end

    [
      ['notify', false, false], ['observe', false, false],
      ['enforce', true, false], ['enforce', false, true]
    ].each do |mode, stop_exempt, suppress_actions|
      it "does not threaten a stop for saved #{mode}/exempt=#{stop_exempt}/suppressed=#{suppress_actions} policy" do
        incident = receive_first_report
        outcome = incident.incident_policy_evaluations.sole
        evaluation = outcome.snapshot.deep_dup
        evaluation.fetch('effective').merge!('mode' => mode, 'stop_exempt' => stop_exempt, 'suppress_actions' => suppress_actions)
        IncidentPolicyEvaluation.where(id: outcome.id).update_all(snapshot: evaluation)

        described_class.fire(VpsAdmin::API::IncidentReports::Result.new(incidents: [incident]))

        mail = ordinary_mail(incident)
        [mail.text_plain, mail.text_html].each_with_index do |body, index|
          if index == 0
            expect(body).to include('7 days | 1 | 5 | Warning', '30 days | 1 | 10 | VPS stop')
          else
            visible = body.gsub(/<[^>]*>/, ' ').split.join(' ')
            expect(visible).to include('7 days 1 5 Warning', '30 days 1 10 VPS stop')
          end
          note = if mode == 'observe' || suppress_actions
                   'Automatic warnings and VPS stopping were disabled for this policy at the time of evaluation.'
                 else
                   'Automatic VPS stopping was disabled for this policy at the time of evaluation.'
                 end
          expect(body).to include(note)
          expect(body).not_to include('warning limit:', 'stop limit:')
          expect(body).not_to include('the VPS may be stopped', 'As of:', 'without warnings', 'do not stop', 'does not trigger')
        end
      end
    end

    def use_mail_policies(&block)
      configuration = IncidentEscalation::Configuration.new
      configuration.instance_eval(&block)
      stub_const('IncidentEscalation::RULES', configuration.rules.sort.to_h.freeze)
      configuration.rules.each_value do |rule|
        SysConfig.create!(category: rule.category, name: 'mode', value: 'enforce', data_type: 'String')
      end
    end

    it 'sends one ordinary mail with lexical saved summaries from two matching policies, even after removal' do
      calls = []
      use_mail_policies do
        rule :zeta do
          labels en: 'Zeta <policy>', cs: 'Zeta <pravidlo>'
          limits warning: 6, stop: 20
          applies_if do
            calls << 'zeta'
            true
          end
        end
        rule :alpha do
          labels en: 'Alpha <policy>', cs: 'Alfa <pravidlo>'
          limits warning: 5, stop: 10
          applies_if do
            calls << 'alpha'
            true
          end
        end
      end
      ordinary = MailTemplate.find_by!(name: 'vps_incident_report')
      incident = nil
      expect { incident = receive_first_report(language: 'cs') }.to change {
        MailLog.where(mail_template: ordinary).count
      }.by(1).and change(IncidentReport, :count).by(1)
      expect(calls).to eq(%w[alpha zeta])
      mail = ordinary_mail(incident)
      language = MailTemplate.mail_template_translation_for(ordinary, incident.user.language).language.code
      summaries = VpsAdmin::API::IncidentReports.mail_policies(incident, language:)
      expect(summaries.pluck(:key)).to eq(%w[alpha zeta])
      expect(summaries.pluck(:stop_limit)).to eq([10, 20])
      expect(mail.text_plain.index(summaries.first[:label])).to be < mail.text_plain.index(summaries.last[:label])
      expect(mail.text_html).to include(ERB::Util.html_escape(summaries.first[:label]))
      sentence = language == 'cs' ? 'Pokud se tato situace bude opakovat, VPS může být vypnuto.' : 'If this happens again, the VPS may be stopped.'
      expect(mail.text_plain.scan(sentence).length).to eq(1)
      original = mail.attributes.deep_dup
      stub_const('IncidentEscalation::RULES', {}.freeze)
      allow(IncidentEscalation).to receive(:config).and_raise('rendering must not query current policy')

      expect { described_class.fire(VpsAdmin::API::IncidentReports::Result.new(incidents: [incident])) }.to change {
        MailLog.where(mail_template: ordinary).count
      }.by(1)

      expect(ordinary_mail(incident).text_plain).to eq(mail.text_plain)
      expect(mail.reload.attributes).to eq(original)
      expect(calls).to eq(%w[alpha zeta])
    end

    it 'sends source facts only when all creation-time policy results are skipped or errors' do
      use_mail_policies do
        rule :skipped do
          labels en: 'Skipped policy'
          limits warning: 5, stop: 10
          applies_if { false }
        end
        rule :broken do
          labels en: 'Broken policy'
          limits warning: 5, stop: 10
          applies_if { raise 'private selector detail' }
        end
      end
      incident = receive_first_report
      expect(incident.incident_policy_evaluations.order(:policy_key).pluck(:state)).to eq(%w[error skipped])
      incident.incident_policy_evaluations.create!(policy_key: 'audit', matched: true, state: 'audit_only',
                                                   evaluated_at: incident.detected_at, snapshot: {})
      expect(VpsAdmin::API::IncidentReports.mail_policies(incident)).to eq([])
      [ordinary_mail(incident).text_plain, ordinary_mail(incident).text_html].each do |body|
        expect(body).to include('used excessive shared system resources')
        expect(body).not_to include('Incident summary:', 'Broken policy', 'Skipped policy', 'private selector detail')
      end
    end

    it 'renders a manual report with an old producer payload and no policy variable' do
      configured = IncidentEscalation::RULES
      stub_const('IncidentEscalation::RULES', {})
      incident = create_send_incident!(text: "Historical source text\nwith existing explanation\n")
      stub_const('IncidentEscalation::RULES', configured)
      vars = { user: incident.user, vps: incident.vps, incident:, base_url: nil }
      mail = MailTemplate.send_mail!(:vps_incident_report, user: incident.user, vars:)

      expect(mail.text_plain).to include(incident.text)
      expect(mail.text_plain).not_to include('Incident summary:', 'Přehled incidentů:', 'warning limit:', 'limit upozornění:')
      expect(mail.text_html).to include('Historical source text')
      expect(incident.reload.incident_policy_evaluations).to be_empty

      current = create_send_incident!(text: 'Current manual source text')
      evaluation = current.incident_policy_evaluations.sole
      expect(evaluation).to have_attributes(matched: false, state: 'skipped')
      saved = evaluation.attributes
      mails = MailLog.maximum(:id) || 0
      described_class.fire(VpsAdmin::API::IncidentReports::Result.new(incidents: [incident, current]))
      sent = MailLog.where('id > ?', mails).order(:id).to_a
      expect(sent.size).to eq(2)
      expect(sent.map(&:text_plain).join).to include(incident.text, current.text)
      sent.each do |source_mail|
        expect(source_mail.text_plain).not_to include('Incident summary:', 'Přehled incidentů:')
      end
      expect(incident.reload.incident_policy_evaluations).to be_empty
      expect(evaluation.reload.attributes).to eq(saved)
    end
  end
end
