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

  it 'routes a standalone dataset expansion event without operation correlation' do
    fixture = build_active_dataset_expansion_fixture(user: SpecSeed.user)
    expansion = fixture.fetch(:expansion)
    vps = fixture.fetch(:vps)

    chain, = described_class.fire2(args: [expansion])

    expect(chain).to be_nil
    event = expect_completed_event!('vps.dataset_expanded', user: vps.user)
    expect(event.vps).to eq(vps)
    expect(event.source).to eq(expansion)
    expect(event.parameters).not_to have_key('operation_id')
    expect(event.parameters).to include(
      'vps_id' => vps.id,
      'vps_hostname' => vps.hostname,
      'dataset_id' => fixture.fetch(:dataset).id,
      'dataset_full_name' => fixture.fetch(:dataset).full_name,
      'added_space' => expansion.added_space
    )
  end
end
