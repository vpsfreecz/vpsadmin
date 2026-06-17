# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::IncidentReport::Reply do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
    allow(MailTemplate).to receive(:send_custom).and_return(build_mail_log_double)
  end

  def message
    Mail.new.tap do |mail|
      mail.message_id = '<incident-source@test.invalid>'
      mail.subject = 'Abuse report'
    end
  end

  def result_for(count)
    fixture = build_standalone_vps_fixture(user: SpecSeed.user)
    vps = fixture.fetch(:vps)
    assignment = create_ip_assignment_fixture!(vps:)
    mailbox = create_mailbox_fixture!

    incidents = count.times.map do |i|
      create_incident_report_fixture!(
        vps:,
        user: vps.user,
        ip_address_assignment: assignment,
        mailbox:,
        subject: "Incident #{i}",
        text: 'body'
      )
    end

    VpsAdmin::API::IncidentReports::Result.new(
      incidents:,
      reply: {
        from: 'abuse@test.invalid',
        to: ['sender@test.invalid']
      }
    )
  end

  it 'generates a custom reply with threading headers and a reply subject' do
    result = result_for(2)

    chain, = described_class.fire2(args: [message, result])

    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(MailTemplate).to have_received(:send_custom).with(
      hash_including(
        from: 'abuse@test.invalid',
        to: ['sender@test.invalid'],
        in_reply_to: 'incident-source@test.invalid',
        references: 'incident-source@test.invalid',
        subject: 'Re: Abuse report'
      )
    )
    event = Event.where(event_type: 'incident_report.reply').sole
    delivery = event.event_deliveries.sole
    expect(event.user).to be_nil
    expect(event.parameters).to include(
      'from_email' => 'abuse@test.invalid',
      'recipient_emails' => ['sender@test.invalid'],
      'in_reply_to_message_id' => 'incident-source@test.invalid',
      'references_message_id' => 'incident-source@test.invalid',
      'incident_count' => 2,
      'user_count' => 1,
      'vps_count' => 1
    )
    expect(event.parameters.fetch('incident_ids')).to match_array(result.incidents.map(&:id))
    expect(delivery).to be_queued_state
    expect(delivery).to be_direct_email_delivery
    expect(delivery.target_kind).to eq('custom')
    expect(delivery.target_value).to eq('sender@test.invalid')
  end

  it 'uses verbose text for small incident sets' do
    result = result_for(2)

    described_class.fire2(args: [message, result])

    expect(MailTemplate).to have_received(:send_custom).with(
      hash_including(
        text_plain: include(
          'Created 2 incident reports',
          "Incident ##{result.incidents.first.id}"
        )
      )
    )
    event = Event.where(event_type: 'incident_report.reply').sole
    expect(event.parameters.fetch('text')).to include(
      'Created 2 incident reports',
      "Incident ##{result.incidents.first.id}"
    )
  end

  it 'uses compact text for large incident sets' do
    sent_opts = nil
    allow(MailTemplate).to receive(:send_custom) do |opts|
      sent_opts = opts
      build_mail_log_double
    end
    result = result_for(101)

    described_class.fire2(args: [message, result])

    expect(sent_opts.fetch(:text_plain)).to include('Created 101 incident reports')
    expect(sent_opts.fetch(:text_plain)).not_to include("Incident ##{result.incidents.first.id}:")
    event = Event.where(event_type: 'incident_report.reply').sole
    expect(event.parameters.fetch('incident_ids').length).to eq(VpsAdmin::API::Events::PARAMETER_SAMPLE_LIMIT)
  end

  it 'raises when the event e-mail delivery cannot be queued' do
    allow(MailTemplate).to receive(:send_custom).and_raise(ArgumentError, 'invalid recipient')

    expect do
      described_class.fire2(args: [message, result_for(1)])
    end.to raise_error(
      RuntimeError,
      /failed to queue incident report reply e-mail delivery: ArgumentError: invalid recipient/
    )
  end
end
