# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::IncidentReports do
  around do |example|
    old_config = described_class.instance_variable_get(:@config)
    with_current_context(user: SpecSeed.admin) { example.run }
  ensure
    described_class.instance_variable_set(:@config, old_config)
  end

  let(:mailbox) { create_mailbox_fixture! }
  let(:message) do
    Mail.new.tap do |mail|
      mail.message_id = '<incident-source@test.invalid>'
      mail.subject = 'Abuse report'
    end
  end

  def create_incident!(**attrs)
    fixture = build_standalone_vps_fixture(user: attrs.delete(:user) || SpecSeed.user)
    create_incident_report_fixture!(vps: fixture.fetch(:vps), user: fixture.fetch(:vps).user, **attrs)
  end

  describe '.oomd_event_message' do
    let(:vps) do
      # Verify column readers even when no earlier example instantiated a VPS.
      Vps.define_attribute_methods
      instance_double(Vps, id: 123, hostname: 'host<%= 1 + 1 %>&%{hostname}')
    end

    [nil, '', 'de'].each do |code|
      it "falls back to English for language #{code.inspect} and restores the ambient locale" do
        user = instance_double(User, language: code.nil? ? nil : instance_double(Language, code:))

        ::I18n.with_locale(:cs) do
          message = described_class.oomd_event_message(vps:, user:, action: 'restart')

          expect(message).to eq(
            subject: 'Restart due to abuse',
            text: "VPS #123 #{vps.hostname} used excessive shared system resources and reduced the availability of other VPSes on the node. It was therefore restarted.\n"
          )
          expect(::I18n.locale).to eq(:cs)
        end
      end
    end

    it 'restores the ambient locale on rendering failure' do
      user = instance_double(User, language: instance_double(Language, code: 'cs'))
      allow(VpsAdmin::API::I18n).to receive(:t).with('incident_reports.oomd.stop.subject').and_raise('render failure')

      ::I18n.with_locale(:en) do
        expect { described_class.oomd_event_message(vps:, user:, action: 'stop') }.to raise_error('render failure')
        expect(::I18n.locale).to eq(:en)
      end
    end

    it 'keeps report and ambient languages separate across threads' do
      users = %w[en cs].map { |code| instance_double(User, language: instance_double(Language, code:)) }
      messages = users.map do |user|
        Thread.new do
          ::I18n.with_locale(:cs) do
            [described_class.oomd_event_message(vps:, user:, action: 'stop')[:subject], ::I18n.locale]
          end
        end
      end.map(&:value)

      expect(messages).to eq([
                               ['Stop due to abuse', :cs],
                               ['Zastavení kvůli nadměrnému využívání prostředků', :cs]
                             ])
    end
  end

  describe '.mail_policies' do
    let(:evaluation) do
      {
        'state' => 'recorded',
        'metadata' => { 'labels' => { 'en' => 'Saved policy', 'cs' => 'Uložené pravidlo' } },
        'context' => { 'count_7d' => 1, 'count_30d' => 2, 'owner' => { 'id' => 123 } },
        'effective' => { 'warning_limit' => 5, 'stop_limit' => 10, 'mode' => 'enforce',
                         'stop_exempt' => false, 'suppress_actions' => false, 'reason' => 'private site reason' }
      }
    end
    let(:incident) { IncidentReport.new(text: "Stored source fact\n") }
    let(:outcome) do
      incident.incident_policy_evaluations.build(policy_key: 'alpha', matched: true, state: 'recorded',
                                                 evaluated_at: Time.utc(2026, 1, 10, 12), snapshot: evaluation)
    end

    before { outcome }

    it 'projects only saved facts without current settings, internal context or stored-text mutation' do
      original = incident.attributes.deep_dup
      allow(IncidentEscalation).to receive(:config).and_raise('render must not query current settings')

      expect(described_class.mail_policies(incident)).to eq([
                                                              { key: 'alpha', label: 'Saved policy', evaluated_at: Time.utc(2026, 1, 10, 12), count_7d: 1, count_30d: 2,
                                                                warning_limit: 5, stop_limit: 10, mode: 'enforce', stop_exempt: false,
                                                                suppress_actions: false, warning_period_days: 7, stop_period_days: 30,
                                                                repeat_stop_hours: 24, stop_enforced: true }
                                                            ])
      expect(described_class.mail_policies(incident, language: :cs).sole[:label]).to eq('Uložené pravidlo')
      expect(incident.attributes).to eq(original)
    end

    it 'orders mixed-case keys lexically without depending on database collation' do
      incident.incident_policy_evaluations.build(policy_key: 'Zeta', matched: true, state: 'recorded',
                                                 evaluated_at: outcome.evaluated_at, snapshot: evaluation)
      expect(described_class.mail_policies(incident).pluck(:key)).to eq(%w[Zeta alpha])
    end

    it 'returns an empty collection for a source without saved evaluations' do
      incident.incident_policy_evaluations.target.clear
      expect(described_class.mail_policies(incident)).to eq([])
      expect(incident.text).to eq("Stored source fact\n")
    end

    [['skipped', false], ['error', nil], ['error', true], ['audit_only', true]].each do |state, matched|
      it "omits #{state} matched=#{matched.inspect} policy data" do
        outcome.state = state
        outcome.matched = matched
        outcome.snapshot = {}
        expect(described_class.mail_policies(incident)).to eq([])
        expect(incident.text).to eq("Stored source fact\n")
      end
    end

    it 'omits incomplete or malformed saved values without defaulting to current limits or time' do
      evaluation['effective'].delete('warning_limit')
      outcome.snapshot = evaluation
      expect(described_class.mail_policies(incident)).to eq([])
      evaluation['effective']['warning_limit'] = 5
      evaluation['context']['count_7d'] = nil
      outcome.snapshot = evaluation
      expect(described_class.mail_policies(incident)).to eq([])
      evaluation['context']['count_7d'] = 1
      evaluation['effective']['stop_exempt'] = nil
      outcome.snapshot = evaluation
      expect(described_class.mail_policies(incident)).to eq([])
    end

    [{ 'mode' => 'observe' }, { 'mode' => 'notify' }, { 'stop_exempt' => true },
     { 'suppress_actions' => true }].each do |restriction|
      it "does not claim a future stop under saved restriction #{restriction.inspect}" do
        evaluation['effective'].merge!(restriction)
        outcome.snapshot = evaluation
        expect(described_class.mail_policies(incident).sole).to include(stop_enforced: false)
      end
    end
  end

  describe described_class::Handler do
    it 'returns the processed boolean in dry-run mode without firing chains' do
      result = VpsAdmin::API::IncidentReports::Result.new(incidents: [], processed: true)
      VpsAdmin::API::IncidentReports.config do
        handle_message { |_mailbox, _message, dry_run:| dry_run ? result : nil }
      end
      allow(TransactionChains::IncidentReport::Send).to receive(:fire)
      allow(TransactionChains::IncidentReport::Reply).to receive(:fire)

      ret = described_class.new(mailbox).handle_message(message, dry_run: true)

      expect(ret).to be(true)
      expect(TransactionChains::IncidentReport::Send).not_to have_received(:fire)
      expect(TransactionChains::IncidentReport::Reply).not_to have_received(:fire)
    end

    it 'fires Send for active incidents in execute mode' do
      incident = create_incident!
      result = VpsAdmin::API::IncidentReports::Result.new(incidents: [incident])
      VpsAdmin::API::IncidentReports.config do
        handle_message { |_mailbox, _message, dry_run:| dry_run ? nil : result }
      end
      allow(TransactionChains::IncidentReport::Send).to receive(:fire)

      ret = described_class.new(mailbox).handle_message(message, dry_run: false)

      expect(ret).to be(true)
      expect(TransactionChains::IncidentReport::Send).to have_received(:fire).with(
        result,
        message:
      )
    end

    it 'fires Reply when there are no active incidents but a reply is available' do
      incident = create_incident!
      incident.vps.update_column(:object_state, Vps.object_states[:suspended])
      result = VpsAdmin::API::IncidentReports::Result.new(
        incidents: [incident],
        reply: {
          from: 'abuse@test.invalid',
          to: ['sender@test.invalid']
        }
      )
      VpsAdmin::API::IncidentReports.config do
        handle_message { |_mailbox, _message, dry_run:| dry_run ? nil : result }
      end
      allow(TransactionChains::IncidentReport::Reply).to receive(:fire)

      ret = described_class.new(mailbox).handle_message(message, dry_run: false)

      expect(ret).to be(true)
      expect(TransactionChains::IncidentReport::Reply).to have_received(:fire).with(message, result)
    end
  end

  describe described_class::Parser do
    let(:parser_class) do
      Class.new(VpsAdmin::API::IncidentReports::Parser) do
        public :find_ip_address_assignment
      end
    end
    let(:parser) { parser_class.new(mailbox, message, dry_run: true) }

    def create_parser_vps!
      build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    end

    def create_split24_network!
      Network.find_or_create_by!(address: '198.51.100.0', prefix: 24) do |network|
        network.label = 'Spec parser /24'
        network.ip_version = 4
        network.role = :public_access
        network.managed = true
        network.split_access = :no_access
        network.split_prefix = 24
        network.purpose = :any
        network.primary_location = SpecSeed.location
      end.tap do |network|
        LocationNetwork.find_or_create_by!(location: SpecSeed.location, network:) do |loc_net|
          loc_net.primary = true
          loc_net.priority = 10
          loc_net.autopick = true
          loc_net.userpick = true
        end
      end
    end

    it 'finds an exact address assignment' do
      vps = create_parser_vps!
      assignment = create_ip_assignment_fixture!(vps:)

      expect(parser.find_ip_address_assignment(assignment.ip_addr)).to eq(assignment)
    end

    it 'finds an address from a larger encompassing network' do
      vps = create_parser_vps!
      network = create_split24_network!
      ip = IpAddress.register(
        IPAddress.parse('198.51.100.0/24'),
        network:,
        user: nil,
        location: SpecSeed.location,
        prefix: 24,
        size: 256
      )
      assignment = create_ip_assignment_fixture!(vps:, ip_address: ip)

      expect(parser.find_ip_address_assignment('198.51.100.25')).to eq(assignment)
    end

    it 'returns nil when no address matches' do
      expect(parser.find_ip_address_assignment('203.0.113.10')).to be_nil
    end

    it 'picks the current time-bounded assignment' do
      old_vps = create_parser_vps!
      current_vps = create_parser_vps!
      ip = create_ip_address!(
        network: SpecSeed.network_v4,
        location: SpecSeed.location,
        user: nil
      )
      old_assignment = create_ip_assignment_fixture!(
        vps: old_vps,
        ip_address: ip,
        from_date: 3.days.ago,
        to_date: 2.days.ago
      )
      current_assignment = create_ip_assignment_fixture!(
        vps: current_vps,
        ip_address: ip,
        from_date: 1.day.ago,
        to_date: nil
      )

      expect(parser.find_ip_address_assignment(ip.ip_addr, time: Time.now.utc)).to eq(current_assignment)
      expect(parser.find_ip_address_assignment(ip.ip_addr, time: old_assignment.from_date + 1.hour))
        .to eq(old_assignment)
    end
  end
end
