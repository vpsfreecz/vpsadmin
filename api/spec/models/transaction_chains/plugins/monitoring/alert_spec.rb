# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'monitoring alert chain', requires_plugins: :monitoring do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def build_event
    MonitoredEvent.create!(
      monitor_name: 'alert_chain',
      class_name: SpecSeed.user.class.name,
      row_id: SpecSeed.user.id,
      state: :confirmed,
      user: SpecSeed.admin,
      access_level: 0
    ).tap do |event|
      event.object = SpecSeed.user
    end
  end

  it 'concerns the monitored object, invokes the action, and increments alert count when non-empty' do
    event = build_event
    allow(event).to receive(:call_action) do |chain, _ev|
      chain.append_t(Transactions::Utils::NoOp, args: SpecSeed.node.id)
    end

    chain, = chain_class.fire2(args: [event])

    expect(event).to have_received(:call_action).with(kind_of(TransactionChain), event)
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['User', SpecSeed.user.id]
    )
    expect(event.reload.alert_count).to eq(1)
  end

  it 'does not increment alert count when the action leaves the chain empty' do
    event = build_event
    allow(event).to receive(:call_action)

    chain, = chain_class.fire2(args: [event])

    expect(chain).to be_nil
    expect(event.reload.alert_count).to eq(0)
  end
end
