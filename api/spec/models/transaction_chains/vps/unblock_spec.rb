# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Unblock do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_mailer_available!
  end

  it 'starts the VPS and routes a resume event' do
    fixture = build_standalone_vps_fixture(user: SpecSeed.user)
    vps = fixture.fetch(:vps)
    state = ObjectState.new_log(
      vps,
      :active,
      'policy resolved',
      SpecSeed.admin,
      nil,
      nil
    )
    state.save!

    chain, = described_class.fire(vps, true, nil, state)

    expect(tx_classes(chain)).to include(
      Transactions::Vps::Start,
      Transactions::EventDelivery::Release
    )
    event = expect_routed_event!('vps.resumed', user: vps.user)
    expect(event.vps).to eq(vps)
    expect(event.source).to eq(state)
    expect(event.parameters).to include(
      'vps_id' => vps.id,
      'vps_hostname' => vps.hostname,
      'state' => 'active',
      'reason' => 'policy resolved'
    )
  end
end
