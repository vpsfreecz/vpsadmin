# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::OomPrevention do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_mail_templates!
    ensure_mailer_available!
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
  end

  def create_vps!
    build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
  end

  def fire_prevention(vps, action)
    described_class.fire2(
      kwargs: {
        vps:,
        action:,
        ooms_in_period: 12,
        period_seconds: 600
      }
    )
  end

  it 'uses Vps::Restart for restart actions' do
    vps = create_vps!

    chain, prevention = fire_prevention(vps, :restart)

    expect(prevention).to be_persisted
    expect(tx_classes(chain)).to include(Transactions::Vps::Restart)
  end

  it 'uses Vps::Stop for stop actions' do
    vps = create_vps!

    chain, prevention = fire_prevention(vps, :stop)

    expect(prevention).to be_persisted
    expect(tx_classes(chain)).to include(Transactions::Vps::Stop)
  end

  it 'raises for invalid actions' do
    vps = create_vps!

    expect do
      fire_prevention(vps, :suspend)
    end.to raise_error(ArgumentError, 'unknown action :suspend')
  end

  it 'creates an OomPrevention row and sends prevention mail' do
    vps = create_vps!

    expect do
      fire_prevention(vps, :restart)
    end.to change(OomPrevention, :count).by(1)

    prevention = OomPrevention.last
    expect(prevention.vps).to eq(vps)
    expect(prevention.action).to eq('restart')
    expect(MailTemplate).to have_received(:send_mail!).with(
      :vps_oom_prevention,
      hash_including(
        user: vps.user,
        vars: hash_including(
          vps:,
          action: :restart,
          ooms_in_period: 12,
          period_seconds: 600
        )
      )
    )
  end
end
