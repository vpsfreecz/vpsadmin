# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Passwd do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'passes the generated password through the transaction payload and only logs the action' do
    fixture = build_standalone_vps_fixture(user: user, hostname: 'passwd-change')
    vps = fixture.fetch(:vps)

    chain, = described_class.fire(vps, 'phase2-secret')
    history = ObjectHistory.where(tracked_object: vps, event_type: 'passwd').sole

    expect(tx_classes(chain)).to eq([Transactions::Vps::Passwd])
    expect(tx_payload(chain, Transactions::Vps::Passwd)).to include(
      'user' => 'root',
      'password' => 'phase2-secret'
    )
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', vps.id])
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['Vps', vps.id])
    expect(confirmations_for(chain).map(&:class_name)).to eq(['ObjectHistory'])
    expect(history.event_data).to be_nil
  end
end
