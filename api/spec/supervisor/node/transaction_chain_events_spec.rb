# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'timeout'
require 'vpsadmin/api/events/operation_lifecycle'

RSpec.describe VpsAdmin::Supervisor::Node::TransactionChainEvents do
  def create_chain!(state: :queued, name: 'spec_chain_state',
                    type: 'TransactionChain', user: SpecSeed.user)
    TransactionChain.create!(
      name:,
      type:,
      state:,
      size: 3,
      progress: 2,
      user:,
      user_session: create_session!(user:),
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

  def add_result_descriptor!(chain, event_type: 'resource.updated',
                             user_id: chain.user_id)
    Transaction.create!(
      transaction_chain: chain,
      node: SpecSeed.node,
      handle: Transactions::Utils::NoOp.t_type,
      queue: 'general',
      input: {
        input: {
          result_events: [
            {
              event_type:,
              user_id:,
              source_class: 'User',
              source_id: chain.user_id,
              subject: 'Deferred result fact',
              payload: {
                resource_type: 'User',
                resource_id: chain.user_id,
                action: 'updated',
                changed_fields: ['state']
              }
            }
          ]
        }
      }.to_json,
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

  def create_session!(user: SpecSeed.user)
    UserSession.create!(
      user:,
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

  def process_chain_event(supervisor, chain, previous_state:, state:,
                          producer_event_id: nil, at: nil)
    at ||= Time.utc(2026, 6, 19, 12, 0, 0, 123_456)
    supervisor.send(
      :process_event,
      {
        'chain_id' => chain.id,
        'previous_state' => previous_state,
        'state' => state,
        'time' => at.to_i,
        'time_f' => at.to_f,
        'producer_event_id' => producer_event_id
      }.compact
    )
  end

  it 'defines non-default-routed operation lifecycle event types' do
    VpsAdmin::API::Events::OperationLifecycle::EVENT_TYPES.each do |event_name|
      definition = VpsAdmin::API::Events.type_for(event_name)

      expect(definition).to have_attributes(
        category: 'transactions',
        roles: %w[account admin],
        default_routed: false
      )
    end
  end

  it 'persists a transaction chain state-change event from node messages' do
    chain = create_chain!(state: :failed)
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'Vps',
      row_id: 123
    )
    supervisor = described_class.new(nil, SpecSeed.node)

    expect do
      process_chain_event(supervisor, chain, previous_state: 'rollbacking', state: 'failed')
    end.to change(Event.where(event_type: 'transaction_chain.state_changed'), :count).by(1)
  end

  it 'commits a node message before manually acknowledging it' do
    chain = create_chain!(
      state: :done,
      name: 'start',
      type: 'TransactionChains::Vps::Start'
    )
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'Vps',
      row_id: build_standalone_vps_fixture.fetch(:vps).id
    )
    channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
    supervisor = described_class.new(channel, SpecSeed.node)
    supervisor.start
    queue = channel.queues.fetch(
      "node:#{SpecSeed.node.domain_name}:transaction_chain_events"
    )
    allow(channel).to receive(:ack) do |delivery_tag|
      expect(
        Event.where(
          event_type: 'transaction_chain.state_changed',
          source_class: 'TransactionChain',
          source_id: chain.id
        )
      ).to exist
      channel.acked_tags << delivery_tag
    end

    queue.publish(
      {
        events: [
          {
            chain_id: chain.id,
            previous_state: 'queued',
            state: 'done',
            producer_event_id: '00000000-0000-4000-8000-000000000001',
            time_f: Time.now.to_f
          }
        ]
      }.to_json
    )

    expect(queue.subscribe_kwargs).to include(manual_ack: true)
    expect(channel.acked_tags).to eq([1])
  end

  it 'does not acknowledge or retain partial Events when a message fails' do
    chain = create_chain!(state: :done)
    channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
    described_class.new(channel, SpecSeed.node).start
    queue = channel.queues.fetch(
      "node:#{SpecSeed.node.domain_name}:transaction_chain_events"
    )

    expect do
      queue.publish(
        {
          events: [
            {
              chain_id: chain.id,
              previous_state: 'queued',
              state: 'done',
              producer_event_id: '00000000-0000-4000-8000-000000000002'
            },
            {
              chain_id: chain.id,
              producer_event_id: '00000000-0000-4000-8000-000000000003'
            }
          ]
        }.to_json
      )
    end.to raise_error(KeyError, /state/)

    expect(channel.acked_tags).to be_empty
    expect(
      Event.where(
        event_type: 'transaction_chain.state_changed',
        source_class: 'TransactionChain',
        source_id: chain.id
      )
    ).to be_empty
  end

  it 'deduplicates a redelivered producer transition using the persisted Event' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    chain = create_chain!(
      state: :done,
      name: 'start',
      type: 'TransactionChains::Vps::Start'
    )
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'Vps',
      row_id: vps.id
    )
    supervisor = described_class.new(nil, SpecSeed.node)

    2.times do
      process_chain_event(
        supervisor,
        chain,
        previous_state: 'queued',
        state: 'done',
        producer_event_id: '00000000-0000-4000-8000-000000000004'
      )
    end

    events = Event.where(
      source_class: 'TransactionChain',
      source_id: chain.id,
      event_type: %w[
        transaction_chain.state_changed
        operation.succeeded
      ]
    )
    expect(events.group(:event_type).count).to eq(
      'transaction_chain.state_changed' => 1,
      'operation.succeeded' => 1
    )
    expect(events.map { |event| event.parameters['producer_event_id'] }.uniq)
      .to eq(['00000000-0000-4000-8000-000000000004'])
  end

  it 'orders and deduplicates deferred result facts after operation success' do
    chain = create_chain!(state: :done)
    add_result_descriptor!(chain)
    supervisor = described_class.new(nil, SpecSeed.node)

    2.times do
      process_chain_event(
        supervisor,
        chain,
        previous_state: 'queued',
        state: 'done',
        producer_event_id: '10000000-0000-4000-8000-000000000004'
      )
    end

    success = Event.where(
      event_type: 'operation.succeeded',
      source_class: 'TransactionChain',
      source_id: chain.id
    ).sole
    result = Event.where(event_type: 'resource.updated', subject: 'Deferred result fact').sole

    expect(success.id).to be < result.id
    expect(success.parameters['result_event_ids']).to eq([result.id])
    expect(result.parameters).to include(
      'operation_id' => chain.id,
      'operation_attempt' => 1,
      'operation_result_index' => 0
    )
  end

  it 'does not materialize deferred result facts when an operation fails' do
    chain = create_chain!(state: :failed)
    add_result_descriptor!(chain)
    supervisor = described_class.new(nil, SpecSeed.node)

    process_chain_event(
      supervisor,
      chain,
      previous_state: 'rollbacking',
      state: 'failed',
      producer_event_id: '10000000-0000-4000-8000-000000000005'
    )

    expect(Event.where(event_type: 'resource.updated', subject: 'Deferred result fact')).to be_empty
    expect(
      Event.where(
        event_type: 'operation.failed',
        source_class: 'TransactionChain',
        source_id: chain.id
      )
    ).to exist
  end

  it 'persists a successful operation for the affected VPS owner' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    chain = create_chain!(
      state: :done,
      name: 'start',
      type: 'TransactionChains::Vps::Start',
      user: SpecSeed.admin
    )
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'Vps',
      row_id: vps.id
    )
    supervisor = described_class.new(nil, SpecSeed.node)

    process_chain_event(supervisor, chain, previous_state: 'queued', state: 'done')

    event = Event.find_by!(
      event_type: 'operation.succeeded',
      source_class: 'TransactionChain',
      source_id: chain.id
    )
    expect(event).to have_attributes(
      user: vps.user,
      vps:,
      severity: 'info',
      routing_state: 'suppressed',
      created_at: Time.utc(2026, 6, 19, 12, 0, 0, 123_456)
    )
    expect(event.payload).to include(
      'operation_id' => chain.id,
      'attempt' => 1,
      'operation' => 'vps.start',
      'state' => 'done',
      'successful' => true,
      'concern_classes' => ['Vps'],
      'concern_object_ids' => [vps.id],
      'actor_user_id' => SpecSeed.admin.id,
      'user_session_id' => chain.user_session_id,
      'node_id' => SpecSeed.node.id
    )
  end

  it 'keeps an unowned admin operation distinct from its actor' do
    chain = create_chain!(state: :done, user: SpecSeed.admin)
    add_result_descriptor!(chain, user_id: nil)
    supervisor = described_class.new(nil, SpecSeed.node)

    process_chain_event(supervisor, chain, previous_state: 'queued', state: 'done')

    lifecycle = Event.where(
      event_type: 'operation.succeeded',
      source_class: 'TransactionChain',
      source_id: chain.id
    ).sole
    result = Event.where(event_type: 'resource.updated', subject: 'Deferred result fact').sole

    expect(lifecycle).to have_attributes(user: nil)
    expect(lifecycle.parameters['actor_user_id']).to eq(SpecSeed.admin.id)
    expect(result).to have_attributes(user: nil)
  end

  it 'retains the accepted owner after an operation removes its resource' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    chain = create_chain!(
      state: :queued,
      name: 'destroy',
      type: 'TransactionChains::Vps::Destroy',
      user: SpecSeed.admin
    )
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'Vps',
      row_id: vps.id
    )
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'User',
      row_id: vps.user_id
    )
    VpsAdmin::API::Events::OperationLifecycle.emit_started!(chain)

    vps.delete
    chain.update!(state: :done)
    supervisor = described_class.new(nil, SpecSeed.node)
    process_chain_event(supervisor, chain, previous_state: 'queued', state: 'done')

    terminal = Event.find_by!(
      event_type: 'operation.succeeded',
      source_class: 'TransactionChain',
      source_id: chain.id
    )
    expect(terminal).to have_attributes(user: SpecSeed.user, vps: nil)
    expect(terminal.parameters).to include(
      'operation' => 'vps.destroy',
      'attempt' => 1,
      'concern_object_ids' => [vps.id, SpecSeed.user.id]
    )
  end

  it 'emits lifecycle events for non-VPS chains without a central map' do
    chain = create_chain!(
      state: :done,
      name: 'create',
      type: 'TransactionChains::Dataset::Create'
    )
    supervisor = described_class.new(nil, SpecSeed.node)

    process_chain_event(supervisor, chain, previous_state: 'queued', state: 'done')

    event = Event.find_by!(
      event_type: 'operation.succeeded',
      source_class: 'TransactionChain',
      source_id: chain.id
    )
    expect(event.user).to eq(chain.user)
    expect(event.payload['operation']).to eq('dataset.create')
  end

  it 'correlates failed and retried attempts with one operation ID' do
    provisional_vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    chain = create_chain!(
      state: :queued,
      name: 'create',
      type: 'TransactionChains::Vps::Create',
      user: SpecSeed.admin
    )
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'Vps',
      row_id: provisional_vps.id
    )
    TransactionChainConcern.create!(
      transaction_chain: chain,
      class_name: 'User',
      row_id: provisional_vps.user_id
    )
    VpsAdmin::API::Events::OperationLifecycle.emit_started!(chain)

    provisional_vps.delete
    supervisor = described_class.new(nil, SpecSeed.node)
    process_chain_event(
      supervisor,
      chain,
      previous_state: 'rollbacking',
      state: 'failed',
      producer_event_id: '00000000-0000-4000-8000-000000000005'
    )
    process_chain_event(
      supervisor,
      chain,
      previous_state: 'failed',
      state: 'queued',
      producer_event_id: '00000000-0000-4000-8000-000000000006'
    )
    process_chain_event(
      supervisor,
      chain,
      previous_state: 'queued',
      state: 'done',
      producer_event_id: '00000000-0000-4000-8000-000000000007'
    )

    lifecycle = Event.where(
      event_type: VpsAdmin::API::Events::OperationLifecycle::EVENT_TYPES,
      source_class: 'TransactionChain',
      source_id: chain.id
    ).order(:id)
    expect(lifecycle.map(&:event_type)).to eq(
      %w[
        operation.started
        operation.failed
        operation.started
        operation.succeeded
      ]
    )
    expect(lifecycle.map { |event| event.parameters['operation_id'] }.uniq)
      .to eq([chain.id])
    expect(lifecycle.map { |event| event.parameters['attempt'] })
      .to eq([1, 1, 2, 2])
    expect(lifecycle.map(&:user_id).uniq).to eq([SpecSeed.user.id])
  end

  it 'emits a resolved event for the current failed attempt' do
    chain = create_chain!(state: :resolved)
    VpsAdmin::API::Events::OperationLifecycle.emit_started!(chain)
    VpsAdmin::API::Events::OperationLifecycle.emit_failed!(chain, state: 'failed')
    supervisor = described_class.new(nil, SpecSeed.node)

    process_chain_event(
      supervisor,
      chain,
      previous_state: 'failed',
      state: 'resolved',
      producer_event_id: '00000000-0000-4000-8000-000000000008'
    )

    event = Event.find_by!(
      event_type: 'operation.resolved',
      source_class: 'TransactionChain',
      source_id: chain.id
    )
    expect(event.parameters).to include(
      'operation_id' => chain.id,
      'attempt' => 1,
      'state' => 'resolved'
    )
  end

  it 'retains out-of-order state transitions with distinct producer IDs' do
    chain = create_chain!(state: :done)
    supervisor = described_class.new(nil, SpecSeed.node)
    newer_time = Time.utc(2026, 6, 19, 12, 0, 2)
    older_time = newer_time - 1

    process_chain_event(
      supervisor,
      chain,
      previous_state: 'queued',
      state: 'done',
      producer_event_id: '00000000-0000-4000-8000-000000000009',
      at: newer_time
    )
    process_chain_event(
      supervisor,
      chain,
      previous_state: 'queued',
      state: 'rollbacking',
      producer_event_id: '00000000-0000-4000-8000-00000000000a',
      at: older_time
    )

    transitions = Event.where(
      event_type: 'transaction_chain.state_changed',
      source_class: 'TransactionChain',
      source_id: chain.id
    ).index_by { |event| event.parameters['producer_event_id'] }
    expect(transitions.keys).to contain_exactly(
      '00000000-0000-4000-8000-00000000000a',
      '00000000-0000-4000-8000-000000000009'
    )
    expect(
      transitions.fetch('00000000-0000-4000-8000-00000000000a').parameters
    ).to include(
      'state' => 'rollbacking',
      'changed_at_timestamp' => older_time.to_f
    )
    expect(
      transitions.fetch('00000000-0000-4000-8000-000000000009').parameters
    ).to include(
      'state' => 'done',
      'changed_at_timestamp' => newer_time.to_f
    )
  end

  %w[failed fatal].each do |state|
    it "persists a #{state} operation using its provisional concern ID" do
      missing_vps_id = Vps.maximum(:id).to_i + 10_000
      chain = create_chain!(
        state: state,
        name: 'create',
        type: 'TransactionChains::Vps::Create'
      )
      TransactionChainConcern.create!(
        transaction_chain: chain,
        class_name: 'Vps',
        row_id: missing_vps_id
      )
      supervisor = described_class.new(nil, SpecSeed.node)

      process_chain_event(supervisor, chain, previous_state: 'rollbacking', state:)

      event = Event.find_by!(
        event_type: 'operation.failed',
        source_class: 'TransactionChain',
        source_id: chain.id
      )
      expect(event).to have_attributes(
        user: chain.user,
        vps: nil,
        severity: state == 'fatal' ? 'critical' : 'error'
      )
      expect(event.payload).to include(
        'operation_id' => chain.id,
        'attempt' => 1,
        'operation' => 'vps.create',
        'state' => state,
        'successful' => false,
        'concern_object_ids' => [missing_vps_id],
        'actor_user_id' => chain.user_id
      )
    end
  end

  it 'aborts unsent notification deliveries when their transaction chain fails' do
    chain = create_chain!(state: :failed)
    transaction = create_transaction!(chain)
    unsent = create_gated_delivery!(transaction:)
    unsent_mail = create_gated_delivery!(transaction:, mail_log: true)
    grouping = create_gated_delivery!(transaction:, state: :grouping)
    first_member_at = Time.now
    survivor_member_at = first_member_at + 120
    group_key = Digest::SHA256.hexdigest('transaction-gated group')
    group_stream_key = Digest::SHA256.hexdigest('transaction-gated email stream')
    group = EventDeliveryGroup.create!(
      route_owner: SpecSeed.user,
      group_key:,
      labels: {},
      group_wait_seconds: 30,
      group_interval_seconds: 300,
      next_flush_at: first_member_at + 30
    )
    grouping.update!(
      event_delivery_group: group,
      group_key:,
      group_stream_key:,
      group_labels: {},
      group_wait_seconds: 30,
      group_interval_seconds: 300,
      released_at: first_member_at
    )
    survivor = create_gated_delivery!(
      transaction: create_transaction!(create_chain!),
      state: :grouping
    )
    survivor.update!(
      event_delivery_group: group,
      group_key:,
      group_stream_key:,
      group_labels: {},
      group_wait_seconds: 30,
      group_interval_seconds: 300,
      released_at: survivor_member_at
    )
    attempted = create_gated_delivery!(transaction:, state: :released, attempted: true)
    supervisor = described_class.new(nil, SpecSeed.node)

    process_chain_event(supervisor, chain, previous_state: 'rollbacking', state: 'failed')

    expect(unsent.reload).to be_aborted_state
    expect(unsent.error_summary).to include("transaction chain ##{chain.id} failed")
    expect(unsent.event.reload).to be_aborted_routing_state
    expect(unsent.event_routing_context.reload).to be_aborted_routing_state
    expect(unsent_mail.reload).to be_aborted_state
    expect(unsent_mail.mail_log).to be_present
    expect(unsent_mail.event.reload).to be_aborted_routing_state
    expect(unsent_mail.event_routing_context.reload).to be_aborted_routing_state
    expect(grouping.reload).to be_aborted_state
    expect(grouping.event.reload).to be_aborted_routing_state
    expect(grouping.event_routing_context.reload).to be_aborted_routing_state
    expect(survivor.reload).to be_grouping_state
    expect(group.reload.next_flush_at).to be_within(1.second).of(survivor_member_at + 30)
    expect(attempted.reload).to be_released_state
    expect(attempted.event.reload).to be_routed_routing_state
    expect(attempted.event_routing_context.reload).to be_routed_routing_state
  end

  it 'serializes group activation with transaction-chain abort', :real_transactions do
    chain = create_chain!(state: :failed)
    transaction = create_transaction!(chain)
    delivery = create_gated_delivery!(transaction:, state: :released)
    group_key = Digest::SHA256.hexdigest("abort-activation-race-#{delivery.id}")
    delivery.update!(
      group_key:,
      group_labels: {},
      group_wait_seconds: 30,
      group_interval_seconds: 300,
      released_at: Time.now,
      next_attempt_at: Time.now
    )

    abort_locked = Queue.new
    continue_abort = Queue.new
    activation_lock_attempted = Queue.new
    abort_thread = nil
    activation_thread = nil

    allow(VpsAdmin::API::Notifications::GroupActivation)
      .to receive(:lock_transaction_chains!)
      .and_wrap_original do |method, chain_ids|
        activation_lock_attempted << true
        method.call(chain_ids)
      end

    abort_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        EventDelivery.transaction do
          TransactionChain.where(id: chain.id).lock.take
          abort_locked << true
          continue_abort.pop
          EventDelivery.abort_unsent_for_transaction_chain!(chain.id)
        end
      end
    end

    Timeout.timeout(5) { abort_locked.pop }
    activation_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        VpsAdmin::API::Notifications::GroupActivation.activate!(
          EventDelivery.find(delivery.id)
        )
      end
    end
    Timeout.timeout(5) { activation_lock_attempted.pop }
    continue_abort << true

    expect(Timeout.timeout(5) { abort_thread.value }).to eq([delivery.event_id])
    expect(Timeout.timeout(5) { activation_thread.value }).to be_nil
    expect(delivery.reload).to be_aborted_state
    expect(delivery.event_delivery_group_id).to be_nil
    expect(EventDeliveryGroup.where(group_key:).count).to eq(0)
  ensure
    continue_abort << true if continue_abort
    [abort_thread, activation_thread].compact.each do |thread|
      thread.join(5)
      thread.kill if thread.alive?
    end

    if delivery&.persisted?
      EventDeliveryAttempt.where(event_delivery_id: delivery.id).delete_all
      EventDelivery.where(id: delivery.id).delete_all
      EventRoutingContext.where(event_id: delivery.event_id).delete_all
      Event.where(id: delivery.event_id).delete_all
    end
    EventDeliveryGroup.where(group_key:).delete_all if group_key
    Transaction.where(id: transaction&.id).delete_all
    session_id = chain&.user_session_id
    TransactionChain.where(id: chain&.id).delete_all
    UserSession.where(id: session_id).delete_all
  end
end
