# frozen_string_literal: true

require 'json'
require 'securerandom'

module SpecTransactions
  class ChainTx < ::Transaction
    t_type 990_010
    queue :general

    def params(node, tag:)
      self.node = node

      {
        node_id: node.id,
        tag:
      }
    end
  end
end

module SpecChains
  class Empty < ::TransactionChain
    def link_chain(*)
      nil
    end
  end

  class AllowedEmpty < ::TransactionChain
    allow_empty

    def link_chain(*)
      nil
    end
  end

  class AllowedEmptyLocked < ::TransactionChain
    allow_empty

    def link_chain(lock_target)
      lock(lock_target)
      nil
    end
  end

  class AllowedEmptyDeferred < ::TransactionChain
    allow_empty

    def link_chain
      defer_result_event!(
        'os_family.updated',
        user: ::User.current,
        source: ::User.current,
        subject: 'Allowed empty result fact',
        payload: {
          resource_type: 'User',
          resource_id: ::User.current.id,
          action: 'updated',
          changed_fields: ['state']
        }
      )
    end
  end

  class AllowedEmptyCleanupFailure < ::TransactionChain
    allow_empty

    def link_chain(object)
      object&.save!
    end

    def release_locks
      super
      raise 'allowed-empty cleanup failed'
    end
  end

  class Failing < ::TransactionChain
    def link_chain(node)
      concerns(:affect, ['Vps', 987_654])
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'never queued' })
      defer_result_event!(
        'os_family.updated',
        user: ::User.current,
        source: ::User.current,
        subject: 'Rolled back result fact',
        payload: {
          resource_type: 'User',
          resource_id: ::User.current.id,
          action: 'updated',
          changed_fields: ['state']
        }
      )
      raise 'link failed'
    end
  end

  class Linear < ::TransactionChain
    def link_chain(node)
      seen_state = state.to_sym

      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'first' }, name: :first)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'second' }, name: :second)

      seen_state
    end
  end

  class Anchored < ::TransactionChain
    def link_chain(node)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'root' }, name: :root)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'tail' }, name: :tail)
      append_to(:root, SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'branch' }, name: :branch)
    end
  end

  class NoopChain < ::TransactionChain
    def link_chain(node)
      self.last_node_id = node.id

      append_or_noop_t(SpecTransactions::ChainTx, noop: true) do |confirmable|
        row = ResourceLock.create!(resource: 'SpecLock', row_id: 77)
        confirmable.just_destroy(row)
      end
    end
  end

  class Inner < ::TransactionChain
    def link_chain(node, lock_target)
      lock(lock_target)
      concerns(:affect, [lock_target.class.name, lock_target.id])
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'inner-1' }, name: :inner1)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'inner-2' }, name: :inner2)
    end
  end

  class Outer < ::TransactionChain
    def link_chain(node, lock_target)
      lock(lock_target)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'outer-1' }, name: :outer1)
      use_chain(SpecChains::Inner, args: [node, lock_target])
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'outer-2' }, name: :outer2)
      concerns(:affect, [lock_target.class.name, lock_target.id])
    end
  end

  class ContextProbe < ::TransactionChain
    def link_chain
      [included?, current_chain]
    end
  end

  class ReleaseOnly < ::TransactionChain
    def link_chain(event)
      release_event_deliveries!(event)
    end
  end

  class VpsConcern < ::TransactionChain
    def link_chain(node, vps)
      concerns(:affect, [vps.class.name, vps.id])
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'vps' })
    end
  end

  class ImmediateEvent < ::TransactionChain
    def link_chain(node)
      event = prepare_event!(
        'os_family.updated',
        user: ::User.current,
        source: ::User.current,
        subject: 'Immediate chain fact',
        payload: {
          resource_type: 'User',
          resource_id: ::User.current.id,
          action: 'updated',
          changed_fields: ['state'],
          'operation_id' => -1
        }
      )
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'event' })
      event
    end
  end

  class ResourceMutation < ::TransactionChain
    def link_chain(node, object, action)
      case action
      when :create
        object.save!
        append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'create' }) do |t|
          t.just_create(object)
        end

      when :update
        original = object.description
        object.update!(description: 'updated in transaction chain')
        defer_resource_event!(:updated, object, changed_fields: %w[description])
        append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'update' }) do |t|
          t.edit_before(object, description: original)
        end

      when :logical_delete
        original = object.description
        object.update!(description: 'logically deleted in transaction chain')
        defer_resource_event!(:updated, object, changed_fields: %w[description])
        append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'logical-delete' }) do |t|
          t.edit_before(object, description: original)
        end

      when :confirmed_delete
        append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'confirmed-delete' }) do |t|
          t.just_destroy(object)
        end

      else
        raise ArgumentError, "unsupported resource action #{action.inspect}"
      end

      object
    end
  end

  class ConstructionFailure < ::TransactionChain
    def link_chain(_node, object)
      object&.save!
      raise 'transaction chain construction failed'
    end
  end

  class PostDeferralFailure < ::TransactionChain
    def link_chain(node, object)
      object&.save!
      append_t(
        SpecTransactions::ChainTx,
        args: [node],
        kwargs: { tag: 'post-deferral-failure' }
      )
    end

    def append_deferred_result_events!
      super
      raise 'deferred result finalization failed'
    end
  end
end

RSpec.describe TransactionChain do
  let(:node) do
    SpecSeed.node.tap do |n|
      n.update!(active: true) unless n.active?
    end
  end
  let(:lock_target) do
    UserClusterResource.find_by!(
      user: SpecSeed.user,
      environment: SpecSeed.environment,
      cluster_resource: ClusterResource.find_by!(name: 'ipv4')
    )
  end

  def with_transaction_chain_resource_policy(action, model: OsFamily, &)
    resource_name =
      VpsAdmin::API::Events::ResourceOperations.resource_name_for(model)
    create_delivery_route!(
      "#{resource_name}.#{action}",
      subject_scope: :visible
    )
    create_delivery_route!(
      'operation.succeeded',
      subject_scope: :visible
    )
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :transaction_chain,
      models: [model.base_class.name],
      reason: 'transaction-chain resource event spec',
      atomic: false,
      resource_action: action
    )
    recorder = VpsAdmin::API::Events::ActionPolicies::Recorder.new(policy)

    VpsAdmin::API::Events::ActionPolicies.with_recorder(recorder, &)
  end

  def blocking_action_boundary(&block)
    create_delivery_route!(
      'os_family.created',
      subject_scope: :visible
    )
    action = Class.new do
      define_singleton_method(:http_method) { :post }
      define_singleton_method(:blocking) { true }
      define_singleton_method(:model) { OsFamily }

      define_method(:initialize) do |work|
        @work = work
      end

      define_method(:safe_exec) do
        @work.call
        [true, {}, {}]
      rescue StandardError => e
        [false, e.message, {}]
      end
    end
    action.prepend(VpsAdmin::API::Events::ActionPolicies::ActionExecution)
    action.new(block)
  end

  def create_delivery_route!(event_type, subject_scope: :self)
    create_spec_event_route!(
      user: SpecSeed.admin,
      event_type:,
      subject_scope:,
      label: "Spec #{event_type} receiver"
    )
  end

  around do |example|
    with_current_context do
      lock_transaction_signer!
      example.run
    end
  end

  it 'builds the chain while staged and queues it afterwards' do
    chain, seen_state = SpecChains::Linear.fire2(args: [node], kwargs: {})

    expect(seen_state).to eq(:staged)
    expect(chain).to be_present
    expect(chain.state).to eq('queued')
    expect(chain.size).to eq(2)
    expect(chain.user_id).to eq(User.current.id)
    expect(chain.user_session_id).to eq(UserSession.current.id)
  end

  it 'does not persist the queued event without a delivery route' do
    chain, = SpecChains::Linear.fire2(args: [node], kwargs: {})
    expect(
      Event.where(
        event_type: 'transaction_chain.state_changed',
        source_class: 'TransactionChain',
        source_id: chain.id
      )
    ).to be_empty
  end

  it 'does not persist the operation start without a delivery route' do
    chain, = SpecChains::Linear.fire2(args: [node], kwargs: {})
    expect(
      Event.where(
        event_type: 'operation.started',
        source_class: 'TransactionChain',
        source_id: chain.id
      )
    ).to be_empty
  end

  it 'allocates the operation start before correlated immediate facts' do
    create_delivery_route!(
      'operation.started',
      subject_scope: :visible
    )
    create_delivery_route!('os_family.updated')
    chain, fact = SpecChains::ImmediateEvent.fire2(args: [node], kwargs: {})
    started = Event.where(
      event_type: 'operation.started',
      source_class: 'TransactionChain',
      source_id: chain.id
    ).sole

    started_delivery = started.event_deliveries.sole
    fact_delivery = fact.event_deliveries.sole
    expect(started_delivery).to be_released_state
    expect(started_delivery.released_at).to be_present
    expect(fact_delivery).to be_prepared_state
    expect(fact_delivery.released_at).to be_nil
    expect(fact.parameters['operation_id']).to eq(chain.id)
    expect(started.parameters['operation_id']).to eq(chain.id)
    expect(EventRouteMatcher.field_value(fact, 'operation_id')).to eq(chain.id)
  end

  it 'persists the primary VPS owner in chain concerns during construction' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)

    chain, = SpecChains::VpsConcern.fire2(args: [node, vps], kwargs: {})
    concerns = chain.transaction_chain_concerns.order(:id).pluck(:class_name, :row_id)

    expect(concerns.last(2)).to eq(
      [
        ['Vps', vps.id],
        ['User', vps.user_id]
      ]
    )
    expect(chain.user).to eq(SpecSeed.admin)
  end

  it 'does not roll back a built chain when its queued Event cannot be emitted' do
    allow(VpsAdmin::API::Events)
      .to receive(:emit_transaction_chain_state!)
      .and_raise('event persistence unavailable')
    allow(SpecChains::Linear).to receive(:warn)

    chain, = SpecChains::Linear.fire2(args: [node], kwargs: {})

    expect(chain).to be_persisted
    expect(chain.reload).to be_queued
    expect(chain.transactions.count).to eq(2)
    expect(SpecChains::Linear).to have_received(:warn).with(
      /Unable to emit transaction chain event for chain ##{chain.id}/
    )
  end

  it 'does not report chain construction failure when start routing fails' do
    create_delivery_route!(
      'operation.started',
      subject_scope: :visible
    )
    allow(VpsAdmin::API::Events::OperationLifecycle)
      .to receive(:route_started!)
      .and_raise('event routing unavailable')
    allow(SpecChains::Linear).to receive(:warn)

    chain, = SpecChains::Linear.fire2(args: [node], kwargs: {})
    started = Event.where(
      event_type: 'operation.started',
      source_class: 'TransactionChain',
      source_id: chain.id
    ).sole

    expect(chain.reload).to be_queued
    expect(started).to be_routed_routing_state
    expect(started.event_deliveries.sole).to be_prepared_state
    expect(SpecChains::Linear).to have_received(:warn).with(
      /Unable to route operation start event: RuntimeError: event routing unavailable/
    )
  end

  it 'does not emit an event when chain construction is rolled back' do
    before_counts = {
      chains: described_class.count,
      concerns: TransactionChainConcern.count,
      events: Event.where(
        event_type: ['transaction_chain.state_changed', 'operation.started']
      ).count,
      result_events: Event.where(subject: 'Rolled back result fact').count
    }

    expect do
      SpecChains::Failing.fire2(args: [node], kwargs: {})
    end.to raise_error(RuntimeError, 'link failed')

    expect(described_class.count).to eq(before_counts[:chains])
    expect(TransactionChainConcern.count).to eq(before_counts[:concerns])
    expect(
      Event.where(event_type: ['transaction_chain.state_changed', 'operation.started']).count
    )
      .to eq(before_counts[:events])
    expect(Event.where(subject: 'Rolled back result fact').count)
      .to eq(before_counts[:result_events])
  end

  it 'defers an action-scoped created resource fact until operation success' do
    resource = OsFamily.new(
      label: "Deferred create #{SecureRandom.hex(4)}",
      description: 'created by transaction chain'
    )

    chain, = with_transaction_chain_resource_policy(:created) do
      SpecChains::ResourceMutation.fire(node, resource, :create)
    end

    expect_deferred_event!(chain, 'os_family.created')
    complete_chain_operation!(chain)
    event = expect_resource_event!(:created, resource, operation: chain)
    succeeded = Event.where(
      event_type: 'operation.succeeded',
      source_class: 'TransactionChain',
      source_id: chain.id
    ).sole
    expect(succeeded.parameters['result_event_ids']).to eq([event.id])
  end

  it 'does not materialize an action-scoped created fact when the operation fails' do
    resource = OsFamily.new(
      label: "Failed create #{SecureRandom.hex(4)}",
      description: 'created by failed transaction chain'
    )

    chain, = with_transaction_chain_resource_policy(:created) do
      SpecChains::ResourceMutation.fire(node, resource, :create)
    end

    fail_chain_operation!(chain)
    expect(
      Event.where(
        event_type: 'os_family.created',
        source_class: 'OsFamily',
        source_id: resource.id
      )
    ).to be_empty
  end

  it 'emits a committed pre-fire mutation when chain construction later fails' do
    resource = nil
    boundary = blocking_action_boundary do
      resource = OsFamily.create!(
        label: "Committed before failed construction #{SecureRandom.hex(4)}"
      )
      SpecChains::ConstructionFailure.fire(node, nil)
    end

    response = boundary.safe_exec

    expect(response.first).to be(false)
    expect(resource.reload).to be_persisted
    expect_resource_event!(:created, resource)
  end

  it 'suppresses a construction-only mutation rolled back with its chain' do
    resource = OsFamily.new(
      label: "Rolled back construction #{SecureRandom.hex(4)}"
    )
    boundary = blocking_action_boundary do
      SpecChains::ConstructionFailure.fire(node, resource)
    end

    response = boundary.safe_exec

    expect(response.first).to be(false)
    expect(OsFamily.where(id: resource.id)).to be_empty
    expect(
      Event.where(
        event_type: 'os_family.created',
        source_class: 'OsFamily',
        source_id: resource.id
      )
    ).to be_empty
  end

  it 'emits a pre-fire mutation when construction fails after deferral' do
    resource = nil
    boundary = blocking_action_boundary do
      resource = OsFamily.create!(
        label: "Committed before failed finalization #{SecureRandom.hex(4)}"
      )
      SpecChains::PostDeferralFailure.fire(node, nil)
    end

    response = boundary.safe_exec

    expect(response.first).to be(false)
    expect(resource.reload).to be_persisted
    expect_resource_event!(:created, resource)
  end

  it 'suppresses a construction mutation when post-deferral work fails' do
    resource = OsFamily.new(
      label: "Rolled back after deferral #{SecureRandom.hex(4)}"
    )
    boundary = blocking_action_boundary do
      SpecChains::PostDeferralFailure.fire(node, resource)
    end

    response = boundary.safe_exec

    expect(response.first).to be(false)
    expect(OsFamily.where(id: resource.id)).to be_empty
    expect(
      Event.where(
        event_type: 'os_family.created',
        source_class: 'OsFamily',
        source_id: resource.id
      )
    ).to be_empty
  end

  it 'emits a pre-fire mutation when allowed-empty cleanup rolls back' do
    resource = nil
    boundary = blocking_action_boundary do
      resource = OsFamily.create!(
        label: "Committed before allowed-empty rollback #{SecureRandom.hex(4)}"
      )
      SpecChains::AllowedEmptyCleanupFailure.fire(nil)
    end

    response = boundary.safe_exec

    expect(response.first).to be(false)
    expect(resource.reload).to be_persisted
    expect_resource_event!(:created, resource)
  end

  it 'suppresses an allowed-empty construction mutation after rollback' do
    resource = OsFamily.new(
      label: "Rolled back with allowed-empty chain #{SecureRandom.hex(4)}"
    )
    boundary = blocking_action_boundary do
      SpecChains::AllowedEmptyCleanupFailure.fire(resource)
    end

    response = boundary.safe_exec

    expect(response.first).to be(false)
    expect(OsFamily.where(id: resource.id)).to be_empty
    expect(
      Event.where(
        event_type: 'os_family.created',
        source_class: 'OsFamily',
        source_id: resource.id
      )
    ).to be_empty
  end

  it 'deduplicates an explicit update descriptor against action-scoped capture' do
    resource = OsFamily.create!(
      label: "Deferred update #{SecureRandom.hex(4)}",
      description: 'before'
    )

    chain, = with_transaction_chain_resource_policy(:updated) do
      SpecChains::ResourceMutation.fire(node, resource, :update)
    end

    expect_deferred_event!(chain, 'os_family.updated')
    complete_chain_operation!(chain)
    event = expect_resource_event!(:updated, resource, operation: chain)
    expect(event.parameters['changed_fields']).to eq(['description'])
    expect(event.parameters.dig('changes', 'description')).to eq(
      'old' => {
        'kind' => 'value',
        'value' => 'before'
      },
      'new' => {
        'kind' => 'value',
        'value' => 'updated in transaction chain'
      }
    )
  end

  it 'carries a target mutation made before fire into the root chain' do
    resource = OsFamily.create!(
      label: "Pre-fire update #{SecureRandom.hex(4)}",
      description: 'before'
    )

    chain, = with_transaction_chain_resource_policy(:updated) do
      resource.update!(description: 'updated before fire')
      SpecChains::Linear.fire(node)
    end

    expect_deferred_event!(chain, 'os_family.updated')
    complete_chain_operation!(chain)
    event = expect_resource_event!(:updated, resource, operation: chain)
    expect(event.parameters['changed_fields']).to eq(['description'])
  end

  it 'uses default delete intent for a logical update descriptor' do
    resource = OsFamily.create!(
      label: "Logical delete #{SecureRandom.hex(4)}",
      description: 'before'
    )

    chain, = with_transaction_chain_resource_policy(:deleted) do
      SpecChains::ResourceMutation.fire(node, resource, :logical_delete)
    end

    expect_deferred_event!(chain, 'os_family.deleted')
    complete_chain_operation!(chain)
    expect_resource_event!(:deleted, resource, operation: chain)
    expect(
      Event.where(
        event_type: 'os_family.updated',
        source_class: 'OsFamily',
        source_id: resource.id
      )
    ).to be_empty
  end

  it 'derives a default delete fact from a confirmation-only mutation' do
    resource = OsFamily.create!(
      label: "Confirmed delete #{SecureRandom.hex(4)}",
      description: 'before'
    )

    chain, = with_transaction_chain_resource_policy(:deleted) do
      SpecChains::ResourceMutation.fire(node, resource, :confirmed_delete)
    end

    expect_deferred_event!(chain, 'os_family.deleted')
    complete_chain_operation!(chain)
    expect_resource_event!(:deleted, resource, operation: chain)
  end

  it 'reports a synchronous lifetime transition using API delete intent' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    log = ObjectState.new_log(
      vps,
      :soft_delete,
      'Deletion requested',
      User.current,
      nil,
      nil
    )

    chain, = with_transaction_chain_resource_policy(:deleted, model: Vps) do
      TransactionChains::Lifetimes::Wrapper.fire(
        vps,
        :soft_delete,
        [:soft_delete],
        true,
        {},
        log
      )
    end

    expect(chain).to be_nil
    expect_resource_event!(:deleted, vps)
    expect(
      Event.where(
        event_type: 'vps.updated',
        source_class: 'Vps',
        source_id: vps.id
      )
    ).to be_empty
  end

  it 'rolls back chain construction when the operation start cannot be persisted' do
    allow(VpsAdmin::API::Events::OperationLifecycle)
      .to receive(:prepare_started!)
      .and_raise('event persistence unavailable')

    expect do
      SpecChains::Linear.fire2(args: [node], kwargs: {})
    end.to raise_error(RuntimeError, 'event persistence unavailable')

    expect(Event.where(event_type: 'operation.started')).to be_empty
    expect(described_class.where(type: 'SpecChains::Linear')).to be_empty
  end

  it 'queues chains without signing when the transaction key is absent' do
    key = SysConfig.find_by!(category: 'core', name: 'transaction_key')
    original_value = key.value
    key.update_columns(value: nil)

    chain, = SpecChains::Linear.fire2(args: [node], kwargs: {})

    expect(chain).to be_present
    expect(chain.transactions.pluck(:signature)).to all(be_nil)
  ensure
    key.update_columns(value: original_value)
  end

  it 'raises for empty chains unless allow_empty is enabled' do
    expect do
      SpecChains::Empty.fire2(args: [], kwargs: {})
    end.to raise_error(RuntimeError, 'empty')
  end

  it 'returns nil for allowed empty chains' do
    expect do
      chain, ret = SpecChains::AllowedEmpty.fire2(args: [], kwargs: {})

      expect(chain).to be_nil
      expect(ret).to be_nil
    end.not_to change(
      Event.where(event_type: ['transaction_chain.state_changed', 'operation.started']),
      :count
    )
  end

  it 'emits an allowed empty result fact atomically without operation correlation' do
    create_delivery_route!('os_family.updated')
    chain, = SpecChains::AllowedEmptyDeferred.fire2(args: [], kwargs: {})

    expect(chain).to be_nil
    event = Event.where(subject: 'Allowed empty result fact').sole
    expect(event.parameters).not_to have_key('operation_id')
    expect(described_class.where(type: 'SpecChains::AllowedEmptyDeferred')).to be_empty
  end

  it 'releases acquired locks when allowed empty chains are discarded' do
    chain, = SpecChains::AllowedEmptyLocked.fire2(args: [lock_target], kwargs: {})

    expect(chain).to be_nil
    expect(
      ResourceLock.where(resource: lock_target.lock_resource_name, row_id: lock_target.id)
    ).to be_empty
  end

  it 'chains append_t dependencies linearly' do
    chain, = SpecChains::Linear.fire2(args: [node], kwargs: {})
    transactions = chain.transactions.order(:id).to_a

    expect(transactions.size).to eq(2)
    expect(transactions[0].depends_on_id).to be_nil
    expect(transactions[1].depends_on_id).to eq(transactions[0].id)
  end

  it 'anchors append_to to the named transaction instead of the tail' do
    chain, = SpecChains::Anchored.fire2(args: [node], kwargs: {})
    transactions = chain.transactions.order(:id).index_by { |t| JSON.parse(t.input).dig('input', 'tag') }

    expect(transactions.fetch('tail').depends_on_id).to eq(transactions.fetch('root').id)
    expect(transactions.fetch('branch').depends_on_id).to eq(transactions.fetch('root').id)
  end

  it 'creates a no-op transaction when append_or_noop_t(noop: true) is used' do
    chain, = SpecChains::NoopChain.fire2(args: [node], kwargs: {})
    transaction = chain.transactions.take!
    confirmations = TransactionConfirmation.where(transaction_id: transaction.id).to_a

    expect(transaction.handle).to eq(Transactions::Utils::NoOp.t_type)
    expect(transaction.queue).to eq('general')
    expect(confirmations.map(&:confirm_type)).to eq(['just_destroy_type'])
  end

  it 'places service-side delivery releases on a live transaction runner node' do
    NodeCurrentStatus.delete_all
    runner = node
    mailer = Node.create!(
      location: runner.location,
      role: :mailer,
      name: "spec-mailer-#{SecureRandom.hex(3)}",
      ip_addr: "198.51.100.#{(Node.maximum(:id).to_i % 200) + 20}",
      cpus: 1,
      total_memory: 512,
      total_swap: 128,
      active: true
    )
    fresh_node_status!(runner, updated_at: 10.seconds.ago.utc)
    fresh_node_status!(mailer, updated_at: Time.now.utc)
    event = Event.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      category: 'user',
      severity: :info,
      routing_state: :routed,
      subject: 'Spec event',
      payload: {}
    )
    event.event_deliveries.create!(
      action: 'email',
      target_kind: :default_recipient,
      state: :prepared
    )

    chain, = SpecChains::ReleaseOnly.fire2(args: [event], kwargs: {})
    transaction = chain.transactions.sole
    delivery = event.event_deliveries.sole.reload

    expect(transaction.handle).to eq(Transactions::EventDelivery::Notify.t_type)
    expect(transaction.name).to eq('Notify')
    expect(transaction.node_id).to eq(runner.id)
    expect(transaction.node_id).not_to eq(mailer.id)
    expect(delivery.transaction_id).to eq(transaction.id)
  end

  it 'preserves ordering across nested use_chain calls' do
    chain, = SpecChains::Outer.fire2(args: [node, lock_target], kwargs: {})
    transactions = chain.transactions.order(:id).to_a
    tags = transactions.to_h { |t| [JSON.parse(t.input).dig('input', 'tag'), t] }

    expect(tags.fetch('inner-1').depends_on_id).to eq(tags.fetch('outer-1').id)
    expect(tags.fetch('inner-2').depends_on_id).to eq(tags.fetch('inner-1').id)
    expect(tags.fetch('outer-2').depends_on_id).to eq(tags.fetch('inner-2').id)
  end

  it 'records concerns only on the root chain' do
    chain, = SpecChains::Outer.fire2(args: [node, lock_target], kwargs: {})

    expect(
      chain.transaction_chain_concerns.order(:id).pluck(:class_name, :row_id)
    ).to eq(
      [
        [lock_target.class.name, lock_target.id],
        ['User', lock_target.user_id]
      ]
    )
  end

  it 'deduplicates locks across nested chains' do
    chain, = SpecChains::Outer.fire2(args: [node, lock_target], kwargs: {})

    locks = ResourceLock.where(
      resource: lock_target.lock_resource_name,
      row_id: lock_target.id,
      locked_by_type: 'TransactionChain',
      locked_by_id: chain.id
    )

    expect(locks.count).to eq(1)
  end

  it 'reports included-chain context correctly' do
    outer = SpecChains::Outer.new
    inner, observed = SpecChains::ContextProbe.use_in(outer, args: [])

    expect(outer.included?).to be(false)
    expect(outer.current_chain).to eq(outer)
    expect(inner.included?).to be(true)
    expect(inner.current_chain).to eq(outer)
    expect(observed).to eq([true, outer])
  end

  it 'rejects legacy mail scheduling' do
    chain = described_class.new

    expect { chain.mail(:daily_report) }.to raise_error(NotImplementedError, /event routing/)
    expect { chain.mail_custom(to: 'user@example.test') }.to raise_error(NotImplementedError, /event routing/)
  end
end
