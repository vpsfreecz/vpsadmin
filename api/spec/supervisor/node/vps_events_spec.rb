# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::VpsEvents do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 17, 0, 0) }

  def event_payload(vps, type:, opts:)
    {
      'id' => vps.id,
      'time' => timestamp.to_i,
      'type' => type,
      'opts' => opts
    }
  end

  describe '#process_event' do
    it 'logs halt events and marks current status as halted' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      status = set_vps_running!(vps)

      supervisor.send(:process_event, event_payload(vps, type: 'exit', opts: { 'exit_type' => 'halt' }))

      expect(status.reload.halted).to be(true)
      history = ObjectHistory.find_by!(tracked_object: vps, event_type: 'halt')
      expect(history.created_at).to eq(timestamp)
    end

    it 'logs reboot events without marking current status as halted' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      status = set_vps_running!(vps)

      supervisor.send(:process_event, event_payload(vps, type: 'exit', opts: { 'exit_type' => 'reboot' }))

      expect(status.reload.halted).to be(false)
      history = ObjectHistory.find_by!(tracked_object: vps, event_type: 'reboot')
      expect(history.created_at).to eq(timestamp)
    end

    it 'creates an incident report for oomd stop events' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      allow(TransactionChains::IncidentReport::New).to receive(:fire).and_return([instance_double(TransactionChain, id: 999), nil])

      supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => 'stop' }))

      incident = IncidentReport.find_by!(vps:, codename: 'oomd')
      expect(incident.user).to eq(vps.user)
      expect(incident.subject).to eq('Stop due to abuse')
      expect(incident.text).to include('was stopped')
      expect(incident.detected_at).to eq(timestamp)
      expect(TransactionChains::IncidentReport::New).to have_received(:fire).with(incident)
      expect(ObjectHistory.find_by!(tracked_object: vps, event_type: 'stop').created_at).to eq(timestamp)
    end

    it 'creates an incident report for oomd restart events' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      allow(TransactionChains::IncidentReport::New).to receive(:fire).and_return([instance_double(TransactionChain, id: 999), nil])

      supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => 'restart' }))

      incident = IncidentReport.find_by!(vps:, codename: 'oomd')
      expect(incident.subject).to eq('Restart due to abuse')
      expect(incident.text).to include('was restarted')
      expect(TransactionChains::IncidentReport::New).to have_received(:fire).with(incident)
      expect(ObjectHistory.find_by!(tracked_object: vps, event_type: 'restart').created_at).to eq(timestamp)
    end

    it 'ignores events for VPSes on another node' do
      foreign_vps = build_standalone_vps_fixture(node: SpecSeed.other_node).fetch(:vps)
      status = set_vps_running!(foreign_vps)
      allow(TransactionChains::IncidentReport::New).to receive(:fire).and_return([instance_double(TransactionChain, id: 999), nil])

      supervisor.send(
        :process_event,
        event_payload(foreign_vps, type: 'exit', opts: { 'exit_type' => 'halt' })
      )
      supervisor.send(
        :process_event,
        event_payload(foreign_vps, type: 'oomd', opts: { 'action' => 'stop' })
      )

      expect(status.reload.halted).to be(false)
      expect(ObjectHistory.where(tracked_object: foreign_vps)).to be_empty
      expect(IncidentReport.where(vps: foreign_vps)).to be_empty
      expect(TransactionChains::IncidentReport::New).not_to have_received(:fire)
    end

    it 'raises on unsupported oomd actions' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)

      expect do
        supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => 'freeze' }))
      end.to raise_error(RuntimeError, /Unsupported oomd action "freeze"/)
    end
  end

  describe 'localized ordinary oomd reports' do
    let(:timestamp) { Time.now.utc.change(usec: 0) }
    let(:vps) { build_standalone_vps_fixture(node:).fetch(:vps) }

    around do |example|
      unlock_transaction_signer!
      with_current_context(user: SpecSeed.admin) { example.run }
    end

    before do
      ensure_alert_mail_templates!
      ensure_mailer_available!
    end

    def receive_oomd(action = 'stop')
      supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => action }))
      IncidentReport.find_by!(vps:, codename: 'oomd')
    end

    {
      'en' => {
        'stop' => ['Stop due to abuse', 'abused shared system resources and was stopped.'],
        'restart' => ['Restart due to abuse', 'abused shared system resources and was restarted.']
      },
      'cs' => {
        'stop' => ['Zastavení kvůli nadměrnému využívání prostředků', 'nadměrně využíval sdílené systémové prostředky, a proto byl zastaven.'],
        'restart' => ['Restart kvůli nadměrnému využívání prostředků', 'nadměrně využíval sdílené systémové prostředky, a proto byl restartován.']
      }
    }.each do |code, actions|
      actions.each do |action, (subject, body)|
        it "stores and renders the ordinary #{action} report in #{code}, independent of the ambient locale" do
          vps.user.update!(language: Language.find_by!(code:))
          vps.update_column(:hostname, 'host<%= 1 + 1 %>&%{hostname}')

          ::I18n.with_locale(code == 'en' ? :cs : :en) do
            incident = receive_oomd(action)

            expect(incident).to have_attributes(user: vps.user, subject:, text: "VPS ##{vps.id} #{vps.hostname} #{body}\n",
                                                detected_at: timestamp, source_kind: 'node_vps_event', source_action: action, source_node_id: node.id)
            expect(incident.notification_processed_at).to be_present
            mail = MailLog.find_by!(user: vps.user, mail_template: MailTemplate.find_by!(name: 'vps_incident_report'))
            expect(mail.text_plain).to include("Subject: #{subject}", incident.text)
            expect(mail.to).to include(vps.user.email)
            expect(ObjectHistory.find_by!(tracked_object: vps, event_type: action).created_at).to eq(timestamp)
            expect(::I18n.locale).to eq(code == 'en' ? :cs : :en)
          end
        end
      end
    end

    it 'uses the owner reloaded under the VPS lock for both report language and ordinary recipient' do
      vps.user.update!(language: Language.find_by!(code: 'en'))
      owner = SpecSeed.other_user
      owner.update!(language: Language.find_by!(code: 'cs'))
      Vps.where(id: vps.id).update_all(user_id: owner.id)

      described_class.record_oomd_event(vps, node:, action: 'stop', time: timestamp)

      incident = IncidentReport.find_by!(vps:, codename: 'oomd')
      expect(incident).to have_attributes(user: owner, subject: 'Zastavení kvůli nadměrnému využívání prostředků')
      expect(MailLog.find_by!(user: owner).text_plain).to include(incident.text)
    end

    it 'deduplicates before rendering and preserves original text, logs and mail after a language change' do
      vps.user.update!(language: Language.find_by!(code: 'cs'))
      allow(VpsAdmin::API::IncidentReports).to receive(:oomd_event_message).and_call_original
      incident = receive_oomd
      original = incident.attributes
      counts = [IncidentReport.count, ObjectHistory.count, TransactionChain.count, MailLog.count]
      vps.user.update!(language: Language.find_by!(code: 'en'))

      receive_oomd

      expect(incident.reload.attributes).to eq(original)
      expect([IncidentReport.count, ObjectHistory.count, TransactionChain.count, MailLog.count]).to eq(counts)
      expect(VpsAdmin::API::IncidentReports).to have_received(:oomd_event_message).once
      expect(IncidentEscalation.new(vps).counts).to eq([1, 1])
    end

    it 'keeps localized reports when ordinary mail is disabled without creating a mail chain' do
      vps.user.update!(language: Language.find_by!(code: 'cs'))
      template = MailTemplate.find_by!(name: 'vps_incident_report')
      UserMailTemplateRecipient.handle_update!(vps.user, template, enabled: false)

      incident = receive_oomd

      expect(incident).to have_attributes(subject: 'Zastavení kvůli nadměrnému využívání prostředků', notification_chain_id: nil)
      expect(incident.notification_processed_at).to be_present
      expect(MailLog.where(mail_template: template)).to be_empty
    end

    it 'retries ordinary mail with the stored language while leaving historical manual reports unchanged' do
      vps.user.update!(language: Language.find_by!(code: 'cs'))
      historical = IncidentReport.create!(vps:, user: vps.user, codename: 'oomd', subject: 'Original subject',
                                          text: "Original manual text\n", detected_at: timestamp - 60)
      allow(TransactionChains::IncidentReport::New).to receive(:fire).and_raise('mail unavailable')
      expect { receive_oomd }.to output(/Unable to queue incident.*mail unavailable/).to_stderr
      incident = IncidentReport.where(vps:).where.not(source_key: nil).sole
      vps.user.update!(language: Language.find_by!(code: 'en'))
      allow(TransactionChains::IncidentReport::New).to receive(:fire).and_call_original

      IncidentEscalation.process!(vps)

      expect(MailLog.find_by!(user: vps.user).text_plain).to include(incident.text, 'Zastavení kvůli nadměrnému využívání prostředků')
      expect(incident.reload.notification_processed_at).to be_present
      expect(historical.reload).to have_attributes(subject: 'Original subject', text: "Original manual text\n")
    end
  end
end
