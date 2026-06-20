# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::StopOverQuota do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_mailer_available!
  end

  it 'locks the VPS, stops it, concerns the VPS and dataset, and schedules over-quota mail' do
    fixture = build_active_dataset_expansion_fixture(user: SpecSeed.user)
    expansion = fixture.fetch(:expansion)

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
      Transactions::EventDelivery::Release
    )
    event = expect_routed_event!('vps.stopped_over_quota', user: fixture.fetch(:vps).user)
    expect(event.vps).to eq(fixture.fetch(:vps))
    expect(event.source).to eq(expansion)
    expect(event.parameters).to include(
      'dataset_id' => fixture.fetch(:dataset).id,
      'dataset_full_name' => fixture.fetch(:dataset).full_name,
      'expansion_id' => expansion.id,
      'original_refquota' => expansion.original_refquota,
      'enable_shrink' => true
    )
  end
end
