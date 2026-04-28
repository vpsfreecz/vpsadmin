# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Mail::VpsDatasetExpanded do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_mail_templates!
    ensure_mailer_available!
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
  end

  it 'targets the affected VPS and sends dataset expansion mail' do
    fixture = build_active_dataset_expansion_fixture(user: SpecSeed.user)
    expansion = fixture.fetch(:expansion)
    vps = fixture.fetch(:vps)

    chain, = described_class.fire2(args: [expansion])

    expect(chain).to be_present
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to eq([['Vps', vps.id]])
    expect(MailTemplate).to have_received(:send_mail!).with(
      :vps_dataset_expanded,
      hash_including(
        user: vps.user,
        vars: hash_including(
          vps:,
          expansion:,
          dataset: fixture.fetch(:dataset)
        )
      )
    )
  end
end
