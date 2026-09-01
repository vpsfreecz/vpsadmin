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
    new_refquota = fixture.fetch(:current_refquota)

    chain, = described_class.fire(expansion, new_refquota:)

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
          dataset: fixture.fetch(:dataset),
          original_refquota: expansion.original_refquota,
          new_refquota:,
          added_space: expansion.added_space,
          referenced: fixture.fetch(:dataset_in_pool).referenced
        )
      )
    )
  end

  it 'requires the exact new refquota' do
    fixture = build_active_dataset_expansion_fixture(user: SpecSeed.user)

    expect { described_class.fire(fixture.fetch(:expansion)) }
      .to raise_error(ArgumentError, /new_refquota/)
  end
end
