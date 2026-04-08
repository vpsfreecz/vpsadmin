# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::ExpandDataset do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'creates the expansion and history rows, raises refquota, and schedules mail when notifications are enabled' do
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)

    fixture = build_dataset_expansion_fixture(
      user: user,
      original_refquota: 10_240,
      added_space: 4_096,
      enable_notifications: true
    )
    dip = fixture.fetch(:dataset_in_pool)
    expansion = fixture.fetch(:expansion)
    original_refquota = dip.refquota

    chain, returned_expansion = described_class.fire(expansion)
    history = expansion.dataset_expansion_histories.order(:id).sole

    expect(returned_expansion).to eq(expansion)
    expect(tx_classes(chain)).to include(
      Transactions::Storage::SetDataset,
      Transactions::Mail::Send,
      Transactions::Utils::NoOp
    )
    expect(tx_payload(chain, Transactions::Storage::SetDataset)).to include(
      'properties' => include('refquota' => [original_refquota, original_refquota + expansion.added_space])
    )
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['DatasetInPool', dip.id])
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['Vps', fixture.fetch(:vps).id],
      ['Dataset', fixture.fetch(:dataset).id]
    )

    expect(expansion.reload.original_refquota).to eq(original_refquota)
    expect(history.added_space).to eq(expansion.added_space)
    expect(history.original_refquota).to eq(original_refquota)
    expect(history.new_refquota).to eq(original_refquota + expansion.added_space)
    expect(history.admin).to eq(user)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'Dataset' &&
        row.row_pks == { 'id' => fixture.fetch(:dataset).id } &&
        row.attr_changes['dataset_expansion_id'] == expansion.id
    end).to be(true)
  end

  it 'does not enqueue mail when notifications are disabled' do
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)

    fixture = build_dataset_expansion_fixture(
      user: user,
      original_refquota: 10_240,
      added_space: 2_048,
      enable_notifications: false
    )

    chain, = described_class.fire(fixture.fetch(:expansion))

    expect(tx_classes(chain)).to include(Transactions::Storage::SetDataset, Transactions::Utils::NoOp)
    expect(tx_classes(chain)).not_to include(Transactions::Mail::Send)
  end
end
