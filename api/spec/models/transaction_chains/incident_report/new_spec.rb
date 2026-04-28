# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::IncidentReport::New do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_mail_templates!
    ensure_mailer_available!
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
  end

  def create_incident!(attrs = {})
    fixture = build_standalone_vps_fixture(user: attrs.delete(:user) || SpecSeed.user)
    vps = fixture.fetch(:vps)
    create_network_interface!(vps, name: 'eth0')
    incident = create_incident_report_fixture!(vps:, user: vps.user, **attrs)

    [fixture.merge(vps:), incident]
  end

  it 'points the concern at the affected VPS and delegates notification to Send' do
    fixture, incident = create_incident!

    allow(TransactionChains::IncidentReport::Send).to receive(:use_in).and_call_original

    chain, = described_class.fire2(args: [incident])

    expect(TransactionChains::IncidentReport::Send).to have_received(:use_in)
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['Vps', fixture.fetch(:vps).id]
    )
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
  end

  it 'uses Vps::Update for CPU limits' do
    _fixture, incident = create_incident!(cpu_limit: 50)

    allow(TransactionChains::Vps::Update).to receive(:use_in).and_call_original

    chain, = described_class.fire2(args: [incident])

    expect(TransactionChains::Vps::Update).to have_received(:use_in)
    expect(tx_classes(chain)).to include(Transactions::Utils::NoOp)
  end

  it 'uses Vps::Stop for stop actions' do
    _fixture, incident = create_incident!(vps_action: :stop)

    allow(TransactionChains::Vps::Stop).to receive(:use_in).and_call_original

    chain, = described_class.fire2(args: [incident])

    expect(TransactionChains::Vps::Stop).to have_received(:use_in)
    expect(tx_classes(chain)).to include(Transactions::Vps::Stop)
  end

  it 'suspends the VPS when requested' do
    fixture, incident = create_incident!(vps_action: :suspend)
    vps = fixture.fetch(:vps)

    chain, = described_class.fire2(args: [incident])

    expect(chain).to be_present
    expect(confirmation_attr_changes(chain, 'Vps', confirm_type: :edit_after_type)).to include(
      include('object_state' => Vps.object_states[:suspended])
    )
    expect(ObjectState.where(class_name: 'Vps', row_id: vps.id).order(:id).last.reason)
      .to include("Incident report ##{incident.id}: #{incident.subject}")
  end

  it 'disables network with an incident reason when requested' do
    fixture, incident = create_incident!(vps_action: :disable_network)
    vps = fixture.fetch(:vps)

    allow(TransactionChains::Vps::EnableNetwork).to receive(:use_in).and_call_original

    chain, = described_class.fire2(args: [incident])

    expect(TransactionChains::Vps::EnableNetwork).to have_received(:use_in).with(
      anything,
      hash_including(
        args: [vps, false],
        kwargs: hash_including(
          reason: "Incident report ##{incident.id}: #{incident.subject}"
        )
      )
    )
    expect(tx_classes(chain)).to include(
      Transactions::NetworkInterface::Disable,
      Transactions::Utils::NoOp,
      Transactions::Mail::Send
    )
    expect(chain.transaction_chain_concerns.pluck(:row_id)).to include(vps.id)
  end
end
