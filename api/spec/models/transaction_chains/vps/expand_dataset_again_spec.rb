# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::ExpandDatasetAgain do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'reuses the current expansion, creates another history row, and expands from the current refquota' do
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)

    fixture = build_active_dataset_expansion_fixture(
      user: user,
      original_refquota: 10_240,
      added_space: 2_048,
      enable_notifications: true
    )
    dip = fixture.fetch(:dataset_in_pool)
    expansion = fixture.fetch(:expansion)
    history = expansion.dataset_expansion_histories.new(
      added_space: 1_024,
      admin: user
    )

    chain, returned_history = described_class.fire(history)

    expect(returned_history).to eq(history)
    expect(tx_classes(chain)).to include(
      Transactions::Storage::SetDataset,
      Transactions::Mail::Send,
      Transactions::Utils::NoOp
    )
    expect(tx_payload(chain, Transactions::Storage::SetDataset)).to include(
      'properties' => include('refquota' => [fixture.fetch(:current_refquota), fixture.fetch(:current_refquota) + 1_024])
    )
    expect(history.reload.original_refquota).to eq(fixture.fetch(:current_refquota))
    expect(history.new_refquota).to eq(fixture.fetch(:current_refquota) + 1_024)
    expect(history.admin).to eq(user)
    expect(expansion.dataset_expansion_histories.count).to eq(2)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'DatasetExpansion' &&
        row.row_pks == { 'id' => expansion.id } &&
        row.attr_changes['added_space'] == 3_072
    end).to be(true)
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['DatasetInPool', dip.id])
  end
end
