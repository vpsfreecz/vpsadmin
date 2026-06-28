# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::TransactionChainEvents do
  def create_chain!(state: :queued)
    TransactionChain.create!(
      name: 'spec_chain_state',
      type: 'TransactionChain',
      state:,
      size: 3,
      progress: 2,
      user: SpecSeed.user,
      user_session: create_session!,
      concern_type: :chain_affect
    )
  end

  def create_session!
    UserSession.create!(
      user: SpecSeed.user,
      auth_type: 'basic',
      api_ip_addr: '192.0.2.10',
      client_ip_addr: '192.0.2.10',
      user_agent: UserAgent.find_or_create!('SpecUA/TransactionChainEvents'),
      client_version: 'SpecUA/TransactionChainEvents',
      scope: ['all'],
      label: 'Spec transaction chain events',
      token_lifetime: :fixed,
      token_interval: 3600
    )
  end

  it 'does not persist an unrouted transaction chain state-change event from node messages' do
    chain = create_chain!(state: :failed)
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'Vps',
      row_id: 123
    )
    supervisor = described_class.new(nil, SpecSeed.node)

    expect do
      supervisor.send(
        :process_event,
        {
          'chain_id' => chain.id,
          'previous_state' => 'rollbacking',
          'state' => 'failed',
          'time' => Time.utc(2026, 6, 19, 12, 0, 0).to_i,
          'time_f' => Time.utc(2026, 6, 19, 12, 0, 0, 123_456).to_f
        }
      )
    end.not_to change(Event.where(event_type: 'transaction_chain.state_changed'), :count)
  end
end
