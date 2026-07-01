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

  def create_transaction!(chain)
    Transaction.create!(
      transaction_chain: chain,
      node: SpecSeed.node,
      handle: Transactions::EventDelivery::Notify.t_type,
      queue: 'general',
      input: '{}',
      done: :waiting,
      reversible: :keep_going
    )
  end

  def create_gated_delivery!(transaction:, state: :prepared, attempted: false, mail_log: false)
    event = Event.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      category: 'user',
      severity: :info,
      routing_state: :routed,
      subject: 'Spec transaction-gated notification',
      payload: {}
    )
    context = event.event_routing_contexts.create!(
      recipient_user: SpecSeed.user,
      subject_relation: 'self',
      source: 'direct_route',
      routing_state: :routed
    )
    delivery = event.event_deliveries.create!(
      event_routing_context: context,
      action: :email,
      target_kind: :default_recipient,
      target_value: 'default',
      target_label: 'Default recipient',
      state:,
      mail_log: mail_log ? create_mail_log! : nil,
      transaction_id: transaction.id
    )

    if attempted
      delivery.update!(attempt_count: 1)
      delivery.event_delivery_attempts.create!(
        action: delivery.action,
        state: :failed,
        attempt_number: 1,
        started_at: Time.now,
        finished_at: Time.now,
        error_summary: 'already attempted'
      )
    end

    delivery
  end

  def create_mail_log!
    MailLog.create!(
      user: SpecSeed.user,
      to: 'recipient@example.test',
      cc: '',
      bcc: '',
      from: 'noreply@example.test',
      subject: 'Spec transaction-gated notification',
      text_plain: 'Spec transaction-gated notification body'
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

  it 'aborts unsent notification deliveries when their transaction chain fails' do
    chain = create_chain!(state: :failed)
    transaction = create_transaction!(chain)
    unsent = create_gated_delivery!(transaction:)
    unsent_mail = create_gated_delivery!(transaction:, mail_log: true)
    attempted = create_gated_delivery!(transaction:, state: :released, attempted: true)
    supervisor = described_class.new(nil, SpecSeed.node)

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

    expect(unsent.reload).to be_aborted_state
    expect(unsent.error_summary).to include("transaction chain ##{chain.id} failed")
    expect(unsent.event.reload).to be_aborted_routing_state
    expect(unsent.event_routing_context.reload).to be_aborted_routing_state
    expect(unsent_mail.reload).to be_aborted_state
    expect(unsent_mail.mail_log).to be_present
    expect(unsent_mail.event.reload).to be_aborted_routing_state
    expect(unsent_mail.event_routing_context.reload).to be_aborted_routing_state
    expect(attempted.reload).to be_released_state
    expect(attempted.event.reload).to be_routed_routing_state
    expect(attempted.event_routing_context.reload).to be_routed_routing_state
  end
end
