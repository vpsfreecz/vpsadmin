# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::IncidentReport::Send do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
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
end
