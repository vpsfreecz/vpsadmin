# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::StopOverQuota do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  it 'locks the VPS, stops it, concerns the VPS and dataset, and schedules over-quota mail' do
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
    fixture = build_active_dataset_expansion_fixture(user: SpecSeed.user)
    expansion = fixture.fetch(:expansion)
    captured_mail = nil
    allow(MailTemplate).to receive(:send_mail!) do |name, opts|
      captured_mail = [name, opts]
      build_mail_log_double
    end

    chain, = described_class.fire(expansion)

    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(
      ['Vps', fixture.fetch(:vps).id]
    )
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['Vps', fixture.fetch(:vps).id],
      ['Dataset', fixture.fetch(:dataset).id]
    )
    expect(tx_classes(chain)).to include(
      Transactions::Vps::Stop,
      Transactions::Mail::Send
    )
    expect(captured_mail.first).to eq(:vps_stopped_over_quota)
    expect(captured_mail.last).to include(user: fixture.fetch(:vps).user)
    expect(captured_mail.last.fetch(:vars)).to include(
      vps: fixture.fetch(:vps),
      expansion: expansion,
      dataset: fixture.fetch(:dataset)
    )
  end
end
