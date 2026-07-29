# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Block do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_notification_templates!
    ensure_mailer_available!
  end

  it 'stops the VPS and routes a suspension event' do
    fixture = build_standalone_vps_fixture(user: SpecSeed.user)
    vps = fixture.fetch(:vps)
    state = ObjectState.new_log(
      vps,
      :suspended,
      'policy violation',
      SpecSeed.admin,
      nil,
      nil
    )
    state.save!

    chain, = described_class.fire(vps, true, nil, state)

    expect(tx_classes(chain)).to include(Transactions::Vps::Stop, Transactions::Utils::NoOp)
    expect(chain.transaction_chain_concerns.find_by!(class_name: 'Vps')).to have_attributes(
      class_name: 'Vps',
      row_id: vps.id
    )
    expect(chain.transaction_chain_concerns.find_by!(class_name: 'User')).to have_attributes(
      row_id: vps.user_id
    )
    expect_deferred_event!(chain, 'vps.suspended')

    fail_chain_operation!(chain)
    expect(Event.where(event_type: 'vps.suspended')).to be_empty

    chain.update!(state: :queued)
    VpsAdmin::API::Events::OperationLifecycle.emit_started!(chain)
    2.times { complete_chain_operation!(chain) }

    event = expect_completed_event!('vps.suspended', user: vps.user)
    expect(Event.where(event_type: 'vps.suspended').count).to eq(1)
    expect(event.vps).to eq(vps)
    expect(event.source).to eq(state)
    expect(event.parameters).to include(
      'operation_id' => chain.id,
      'operation_attempt' => 2,
      'vps_id' => vps.id,
      'vps_hostname' => vps.hostname,
      'state' => 'suspended',
      'reason' => 'policy violation'
    )
  end
end
