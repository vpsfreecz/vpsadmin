# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::IncidentReport::Process do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_mail_templates!
    ensure_mailer_available!
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
  end

  def create_process_incident!(vps: nil, **attrs)
    unless vps
      fixture = build_standalone_vps_fixture(user: attrs.delete(:user) || SpecSeed.user)
      vps = fixture.fetch(:vps)
      create_network_interface!(vps, name: 'eth0')
    end

    create_incident_report_fixture!(vps:, user: vps.user, reported_at: nil, **attrs)
  end

  it 'marks all incidents as reported' do
    incidents = [
      create_process_incident!(subject: 'First incident'),
      create_process_incident!(subject: 'Second incident')
    ]

    described_class.fire2(args: [incidents])

    expect(incidents.map { |inc| inc.reload.reported_at }).to all(be_present)
  end

  it 'deduplicates concerns by VPS' do
    fixture = build_standalone_vps_fixture(user: SpecSeed.user)
    vps = fixture.fetch(:vps)
    create_network_interface!(vps, name: 'eth0')
    incidents = [
      create_process_incident!(vps:, subject: 'First incident'),
      create_process_incident!(vps:, subject: 'Second incident')
    ]

    chain, = described_class.fire2(args: [incidents])

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to eq([['Vps', vps.id]])
  end

  it 'uses Vps::Update for incidents with CPU limits' do
    incident = create_process_incident!(cpu_limit: 25)

    allow(TransactionChains::Vps::Update).to receive(:use_in).and_call_original

    chain, = described_class.fire2(args: [[incident]])

    expect(TransactionChains::Vps::Update).to have_received(:use_in)
    expect(tx_classes(chain)).to include(Transactions::Utils::NoOp)
  end

  it 'mails only active incidents but still updates all selected incidents' do
    active = create_process_incident!(subject: 'Active incident')
    inactive = create_process_incident!(subject: 'Inactive incident')
    inactive.vps.update_column(:object_state, Vps.object_states[:suspended])

    described_class.fire2(args: [[active, inactive]])

    expect(MailTemplate).to have_received(:send_mail!).with(
      :vps_incident_report,
      hash_including(vars: hash_including(incident: active))
    ).once
    expect(MailTemplate).not_to have_received(:send_mail!).with(
      :vps_incident_report,
      hash_including(vars: hash_including(incident: inactive))
    )
    expect(active.reload.reported_at).to be_present
    expect(inactive.reload.reported_at).to be_present
  end
end
