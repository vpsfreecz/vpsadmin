# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'outage reports update chain', requires_plugins: :outage_reports do # rubocop:disable RSpec/DescribeClass
  include OutageReportsSpecHelpers

  let(:chain_class) { VpsAdmin::API::Plugins::OutageReports::TransactionChains::Update }
  let(:lang) { SpecSeed.language }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
    SpecSeed.user.update!(object_state: :active)
  end

  def build_outage(attrs = {}, summary: 'Old summary', **kwattrs)
    create_outage_with_translation!(
      {
        state: :staged,
        outage_type: :planned_outage,
        impact_type: :tbd,
        begins_at: Time.local(2026, 4, 1, 10, 0, 0),
        duration: 30,
        auto_resolve: true
      }.merge(attrs).merge(kwattrs),
      summary: summary,
      description: 'Old description'
    )
  end

  def build_security_advisory
    SecurityAdvisory.create!(
      state: :published,
      name: 'Spec vulnerability',
      created_by: SpecSeed.admin,
      published_by: SpecSeed.admin,
      published_at: Time.local(2026, 4, 1, 9, 0, 0)
    ).tap do |advisory|
      advisory.security_advisory_cves.create!(cve_id: 'CVE-2026-3001')
      advisory.security_advisory_cves.create!(cve_id: 'CVE-2026-3002')
    end
  end

  it 'creates an update and edits outage translations without mailing while staged' do
    outage = build_outage
    allow(NotificationTemplate).to receive(:send_email!)

    chain, ret = chain_class.fire2(args: [
                                     outage,
                                     { duration: 45, state: Outage.states[:staged] },
                                     { lang => { summary: 'New summary', description: 'New description' } },
                                     { send_mail: true }
                                   ])

    outage.reload
    update = outage.outage_updates.order(:id).last
    expect(ret).to eq(outage)
    expect(chain).to be_nil
    expect(update.duration).to eq(45)
    expect(update.outage_translations.find_by!(language: lang).summary).to eq('New summary')
    expect(outage.duration).to eq(45)
    expect(outage.outage_translations.find_by!(language: lang).summary).to eq('New summary')
    expect(NotificationTemplate).not_to have_received(:send_email!)
  end

  it 'announces outages, refreshes affected objects, and threads user mail' do
    outage = build_outage
    advisory = build_security_advisory
    last_report = OutageUpdate.create!(
      outage: outage,
      reported_by: SpecSeed.admin,
      state: :staged,
      begins_at: outage.begins_at,
      duration: outage.duration
    )
    OutageSecurityAdvisory.create!(outage:, security_advisory: advisory)
    OutageUser.create!(outage: outage, user: SpecSeed.user, vps_count: 1, export_count: 0)
    cfg = SysConfig.find_or_initialize_by(category: 'webui', name: 'base_url')
    cfg.data_type ||= 'String'
    cfg.value = 'https://webui.example.test/'
    cfg.save!
    attempts = []

    allow(outage).to receive(:set_affected_vpses)
    allow(outage).to receive(:set_affected_exports)
    allow(outage).to receive(:set_affected_users)
    allow(NotificationTemplate).to receive(:send_email!) do |name, opts|
      attempts << [name, opts]
      build_mail_log_double
    end

    chain, = chain_class.fire2(args: [
                                 outage,
                                 { state: Outage.states[:announced], impact_type: Outage.impact_types[:network] },
                                 { lang => { summary: 'Announced', description: 'Announced desc' } },
                                 { send_mail: true }
                               ])

    outage.reload
    report = outage.outage_updates.order(:id).last
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['Outage', outage.id]
    )
    expect(outage.state).to eq('announced')
    expect(outage.impact_type).to eq('network')
    expect(outage).to have_received(:set_affected_vpses)
    expect(outage).to have_received(:set_affected_exports)
    expect(outage).to have_received(:set_affected_users)

    direct = attempts.find { |_name, opts| opts[:user] == SpecSeed.user }
    expect(direct).not_to be_nil
    expect(Event.where(event_type: 'outage.announced', user_id: nil)).to be_empty
    user_event = Event.where(event_type: 'outage.announced', user: SpecSeed.user).sole
    user_delivery = user_event.event_deliveries.sole
    expect(user_event.source).to eq(report)
    expect(user_event.parameters).to include(
      'role' => 'user',
      'event' => 'announce',
      'affected_user_id' => SpecSeed.user.id,
      'affected_user_login' => SpecSeed.user.login,
      'affected_vps_count' => 0,
      'affected_export_count' => 0
    )
    expect(user_event.parameters.fetch('cves')).to contain_exactly(
      'CVE-2026-3001',
      'CVE-2026-3002'
    )
    expect(user_delivery).to be_prepared_state
    expect(user_delivery.notification_receiver).not_to be_nil
    expect(user_delivery.template_name).to eq('outage_report_role_event')

    expected_direct_reply = "<vpsadmin-outage-#{outage.id}-#{SpecSeed.user.id}-announce@vpsadmin.vpsfree.cz>"
    expect(direct.last[:message_id]).to eq(
      "<vpsadmin-outage-#{outage.id}-#{SpecSeed.user.id}-announce@vpsadmin.vpsfree.cz>"
    )
    expect(direct.last[:in_reply_to]).to eq(expected_direct_reply)
    expect(report.id).not_to eq(last_report.id)

    expect(direct.last.dig(:vars, :webui_url)).to eq('https://webui.example.test')
    expect(direct.last.dig(:vars, :security_advisory_cves)).to contain_exactly(
      hash_including(
        advisory_id: advisory.id,
        advisory_name: 'Spec vulnerability',
        cve_id: 'CVE-2026-3001',
        cve_url: 'https://www.cve.org/CVERecord?id=CVE-2026-3001'
      ),
      hash_including(
        advisory_id: advisory.id,
        advisory_name: 'Spec vulnerability',
        cve_id: 'CVE-2026-3002',
        cve_url: 'https://www.cve.org/CVERecord?id=CVE-2026-3002'
      )
    )
  end

  it 'logs muted deliveries for affected users with muted default notifications' do
    outage = build_outage
    mute_default_notifications_for!(SpecSeed.user)
    OutageUser.create!(outage: outage, user: SpecSeed.user, vps_count: 1, export_count: 0)
    attempts = []

    allow(outage).to receive(:set_affected_vpses)
    allow(outage).to receive(:set_affected_exports)
    allow(outage).to receive(:set_affected_users)
    allow(NotificationTemplate).to receive(:send_email!) do |name, opts|
      attempts << [name, opts]
      build_mail_log_double
    end

    chain_class.fire2(args: [
                        outage,
                        { state: Outage.states[:announced] },
                        { lang => { summary: 'Announced', description: 'Announced desc' } },
                        { send_mail: true }
                      ])

    event = Event.where(event_type: 'outage.announced', user: SpecSeed.user).sole
    delivery = event.event_deliveries.sole
    expect(event).to be_suppressed_routing_state
    expect(event.parameters).to include(
      'role' => 'user',
      'event' => 'announce',
      'affected_user_id' => SpecSeed.user.id
    )
    expect(delivery).to be_skipped_state
    expect(delivery.error_summary).to eq('receiver does not notify')
    expect(attempts.none? { |_name, opts| opts[:user] == SpecSeed.user }).to be(true)
  end

  it 'suppresses mail when requested' do
    outage = build_outage(state: :announced)
    allow(NotificationTemplate).to receive(:send_email!)

    chain, = chain_class.fire2(args: [
                                 outage,
                                 { state: Outage.states[:resolved] },
                                 {},
                                 { send_mail: false }
                               ])

    expect(chain).to be_nil
    expect(outage.reload.state).to eq('resolved')
    expect(NotificationTemplate).not_to have_received(:send_email!)
  end
end
