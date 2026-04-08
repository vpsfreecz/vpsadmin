# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::ShrinkDataset do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'restores refquota, clears the expansion link, resolves the expansion, and schedules mail for active VPSes' do
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)

    fixture = build_active_dataset_expansion_fixture(
      user: user,
      original_refquota: 10_240,
      added_space: 2_048,
      enable_notifications: true
    )
    dip = fixture.fetch(:dataset_in_pool)
    expansion = fixture.fetch(:expansion)

    chain, = described_class.fire(dip, expansion)

    expect(tx_classes(chain)).to include(
      Transactions::Storage::SetDataset,
      Transactions::Mail::Send,
      Transactions::Utils::NoOp
    )
    expect(tx_payload(chain, Transactions::Storage::SetDataset)).to include(
      'properties' => include('refquota' => [fixture.fetch(:current_refquota), expansion.original_refquota])
    )
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'Dataset' &&
        row.row_pks == { 'id' => fixture.fetch(:dataset).id } &&
        row.attr_changes['dataset_expansion_id'].nil?
    end).to be(true)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'DatasetExpansion' &&
        row.row_pks == { 'id' => expansion.id } &&
        row.attr_changes['state'] == DatasetExpansion.states[:resolved]
    end).to be(true)
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['DatasetInPool', dip.id])
  end

  it 'does not enqueue mail when the VPS is not active' do
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)

    fixture = build_active_dataset_expansion_fixture(
      user: user,
      original_refquota: 10_240,
      added_space: 2_048,
      enable_notifications: true
    )
    fixture.fetch(:vps).update!(object_state: :suspended)

    chain, = described_class.fire(fixture.fetch(:dataset_in_pool), fixture.fetch(:expansion))

    expect(tx_classes(chain)).to include(Transactions::Storage::SetDataset, Transactions::Utils::NoOp)
    expect(tx_classes(chain)).not_to include(Transactions::Mail::Send)
  end
end
