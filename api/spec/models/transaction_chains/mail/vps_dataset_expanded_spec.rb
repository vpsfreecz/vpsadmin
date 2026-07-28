# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Mail::VpsDatasetExpanded do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_notification_templates!
    ensure_mailer_available!
  end

  it 'targets the affected VPS and routes a dataset expansion event' do
    fixture = build_active_dataset_expansion_fixture(user: SpecSeed.user)
    expansion = fixture.fetch(:expansion)
    vps = fixture.fetch(:vps)
    new_refquota = fixture.fetch(:current_refquota)

    chain, = described_class.fire(expansion, new_refquota:)

    expect(chain).to be_present
    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Notify)
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to eq(
      [
        ['Vps', vps.id],
        ['User', vps.user_id]
      ]
    )
    event = expect_routed_event!('vps.dataset_expanded', user: vps.user)
    expect(event.vps).to eq(vps)
    expect(event.source).to eq(expansion)
    expect(event.parameters).to include(
      'vps_id' => vps.id,
      'vps_hostname' => vps.hostname,
      'dataset_id' => fixture.fetch(:dataset).id,
      'dataset_full_name' => fixture.fetch(:dataset).full_name,
      'dataset_refquota' => new_refquota,
      'dataset_referenced' => fixture.fetch(:dataset_in_pool).referenced,
      'original_refquota' => expansion.original_refquota,
      'new_refquota' => new_refquota,
      'added_space' => expansion.added_space
    )
  end

  it 'requires the exact new refquota' do
    fixture = build_active_dataset_expansion_fixture(user: SpecSeed.user)

    expect { described_class.fire(fixture.fetch(:expansion)) }
      .to raise_error(ArgumentError, /new_refquota/)
  end
end
