# frozen_string_literal: true

require 'json'
require 'time'

module VpsAdmin::API::Events::OperationLifecycle
  STARTED_EVENT_TYPE = 'operation.started'
  SUCCEEDED_EVENT_TYPE = 'operation.succeeded'
  FAILED_EVENT_TYPE = 'operation.failed'
  RESOLVED_EVENT_TYPE = 'operation.resolved'
  EVENT_TYPES = [
    STARTED_EVENT_TYPE,
    SUCCEEDED_EVENT_TYPE,
    FAILED_EVENT_TYPE,
    RESOLVED_EVENT_TYPE
  ].freeze
  CONCERN_OWNER_RESOLVERS = {
    'User' => ->(object) { object },
    'Vps' => lambda(&:user),
    'Dataset' => lambda(&:user),
    'DatasetExpansion' => ->(object) { object.vps.user },
    'DatasetInPool' => ->(object) { object.dataset.user },
    'DatasetTree' => ->(object) { object.dataset_in_pool.dataset.user },
    'Branch' => ->(object) { object.dataset_tree.dataset_in_pool.dataset.user },
    'Snapshot' => ->(object) { object.dataset.user },
    'SnapshotInPool' => ->(object) { object.snapshot.dataset.user },
    'SnapshotDownload' => lambda(&:user),
    'Export' => lambda(&:user),
    'NetworkInterface' => ->(object) { object.vps.user },
    'Mount' => ->(object) { object.vps.user },
    'DnsZone' => lambda(&:user),
    'DnsServerZone' => ->(object) { object.dns_zone.user },
    'DnsZoneTransfer' => ->(object) { object.dns_zone.user },
    'HostIpAddress' => lambda(&:current_owner),
    'IncidentReport' => lambda(&:user),
    'MigrationPlan' => lambda(&:user),
    'ChangeRequest' => lambda(&:user),
    'RegistrationRequest' => lambda(&:user),
    'UserClusterResource' => lambda(&:user),
    'UserNamespace' => lambda(&:user),
    'UserPayment' => lambda(&:user)
  }.freeze

  module_function

  def prepare_started!(chain)
    emit_operation!(
      chain,
      STARTED_EVENT_TYPE,
      attempt: 1,
      state: 'staged',
      route: false,
      release: false
    )
  end

  def finalize_started!(event, chain)
    chain.transaction_chain_concerns.reset
    attributes = operation_attributes(
      chain,
      STARTED_EVENT_TYPE,
      attempt: 1,
      state: 'queued'
    )
    event.assign_attributes(attributes.except(:occurred_at))
    event.created_at = attributes[:occurred_at]
    event.save!
    event
  end

  def route_started!(event)
    route_event!(event)
  end

  def emit_started!(chain, changed_at: nil, node: nil, producer_event_id: nil)
    attempt = next_attempt(chain)
    existing = find_event(chain, STARTED_EVENT_TYPE, attempt)
    return existing if existing

    emit_operation!(
      chain,
      STARTED_EVENT_TYPE,
      attempt:,
      state: 'queued',
      changed_at:,
      node:,
      producer_event_id:
    )
  end

  def emit_transition!(chain, previous_state:, state:, changed_at: nil,
                       node: nil, producer_event_id: nil)
    case state.to_s
    when 'queued'
      return unless %w[failed fatal resolved].include?(previous_state.to_s)

      emit_started!(
        chain,
        changed_at:,
        node:,
        producer_event_id:
      )
    when 'done'
      emit_succeeded!(
        chain,
        changed_at:,
        node:,
        producer_event_id:
      )
    when 'failed', 'fatal'
      emit_failed!(
        chain,
        state:,
        changed_at:,
        node:,
        producer_event_id:
      )
    when 'resolved'
      emit_resolved!(
        chain,
        changed_at:,
        node:,
        producer_event_id:
      )
    end
  end

  def emit_succeeded!(chain, changed_at: nil, node: nil, producer_event_id: nil)
    attempt = current_attempt(chain)
    existing = find_event(chain, SUCCEEDED_EVENT_TYPE, attempt)
    return existing if existing

    result_events = materialize_result_events!(chain, attempt:, changed_at:)
    event = emit_operation!(
      chain,
      SUCCEEDED_EVENT_TYPE,
      attempt:,
      state: 'done',
      changed_at:,
      node:,
      producer_event_id:,
      extra_payload: { result_event_ids: result_events.map(&:id) },
      route: false,
      release: false
    )
    result_events.each { |result_event| route_event!(result_event) }
    route_event!(event)
    event
  end

  def emit_failed!(chain, state:, changed_at: nil, node: nil,
                   producer_event_id: nil)
    attempt = current_attempt(chain)
    existing = find_event(chain, FAILED_EVENT_TYPE, attempt)
    return existing if existing

    emit_operation!(
      chain,
      FAILED_EVENT_TYPE,
      attempt:,
      state: state.to_s,
      changed_at:,
      node:,
      producer_event_id:
    )
  end

  def emit_resolved!(chain, changed_at: nil, node: nil, producer_event_id: nil)
    attempt = current_attempt(chain)
    existing = find_event(chain, RESOLVED_EVENT_TYPE, attempt)
    return existing if existing

    emit_operation!(
      chain,
      RESOLVED_EVENT_TYPE,
      attempt:,
      state: 'resolved',
      changed_at:,
      node:,
      producer_event_id:
    )
  end

  def emit_operation!(chain, event_type, attempt:, state:, changed_at: nil,
                      node: nil, producer_event_id: nil, extra_payload: {},
                      route: true, release: true)
    VpsAdmin::API::Events.emit!(
      event_type,
      **operation_attributes(
        chain,
        event_type,
        attempt:,
        state:,
        changed_at:,
        node:,
        producer_event_id:,
        extra_payload:
      ),
      route:,
      release:,
      persist: :always
    )
  end

  def operation_attributes(chain, event_type, attempt:, state:, changed_at: nil,
                           node: nil, producer_event_id: nil, extra_payload: {})
    vps = VpsAdmin::API::Events.transaction_chain_vps(chain)
    owner = VpsAdmin::API::Events.transaction_chain_target_owner(chain) ||
            vps&.user ||
            actor_as_owner(chain)
    event_time = changed_at || Time.now
    outcome = event_type.delete_prefix('operation.')
    successful = event_type == SUCCEEDED_EVENT_TYPE
    failed = event_type == FAILED_EVENT_TYPE

    {
      user: owner,
      vps:,
      source_class: ::TransactionChain.name,
      source_id: chain.id,
      subject: "#{operation_label(chain)} #{outcome}"[0, 255],
      summary: "Operation ##{chain.id} attempt ##{attempt} #{outcome}",
      severity: severity(event_type, state),
      payload: operation_payload(
        chain,
        attempt:,
        state:,
        successful:,
        failed:,
        changed_at: event_time,
        node:,
        producer_event_id:
      ).merge(extra_payload),
      ip_addr: chain.user_session&.client_ip_addr || chain.user_session&.api_ip_addr,
      occurred_at: event_time
    }
  end

  def route_event!(event)
    VpsAdmin::API::Events.route!(event)
    VpsAdmin::API::Notifications::Release.release!(
      event.event_deliveries.where(state: 'prepared')
    )
    event
  end

  def operation_payload(chain, attempt:, state:, successful:, failed:,
                        changed_at:, node:, producer_event_id:)
    concerns = chain.transaction_chain_concerns.sort_by(&:id)
    {
      operation_id: chain.id,
      attempt:,
      operation: operation_key(chain),
      operation_label: operation_label(chain),
      chain_name: chain.name,
      chain_type: chain.type,
      state:,
      successful:,
      failed:,
      concern_type: chain.concern_type&.delete_prefix('chain_'),
      concern_classes: concerns.map(&:class_name),
      concern_object_ids: concerns.map(&:row_id),
      actor_user_id: chain.user_id,
      admin_user_id: chain.user_session&.admin_id,
      user_session_id: chain.user_session_id,
      node_id: node&.id,
      node_name: node&.domain_name,
      producer_event_id:,
      changed_at: changed_at.iso8601
    }.compact
  end

  def operation_key(chain)
    klass = chain.type.to_s.safe_constantize
    override = klass.event_operation if klass.respond_to?(:event_operation)
    return override if override.present?

    path = ::TransactionChain.transaction_chain_i18n_path(chain.type)
    path == 'transaction_chain' ? chain.name.to_s : path
  end

  def operation_label(chain)
    chain.label
  rescue StandardError
    chain.name.to_s.humanize
  end

  def severity(event_type, state)
    return :critical if event_type == FAILED_EVENT_TYPE && state.to_s == 'fatal'
    return :error if event_type == FAILED_EVENT_TYPE

    :info
  end

  def next_attempt(chain)
    operation_events(chain, STARTED_EVENT_TYPE)
      .filter_map { |event| event.parameters['attempt'] }
      .map(&:to_i)
      .max
      .to_i + 1
  end

  def current_attempt(chain)
    operation_events(chain, STARTED_EVENT_TYPE)
      .filter_map { |event| event.parameters['attempt'] }
      .map(&:to_i)
      .max || 1
  end

  def find_event(chain, event_type, attempt)
    operation_events(chain, event_type).detect do |event|
      event.parameters['attempt'].to_i == attempt
    end
  end

  def operation_events(chain, event_type)
    ::Event.where(
      event_type:,
      source_class: ::TransactionChain.name,
      source_id: chain.id
    ).order(:id)
  end

  def materialize_result_events!(chain, attempt:, changed_at: nil)
    result_descriptors(chain).each_with_index.map do |descriptor, index|
      existing = result_event(chain, index)
      next existing if existing

      emit_result_descriptor!(
        chain,
        descriptor,
        attempt:,
        index:,
        changed_at:,
        correlate: true,
        route: false,
        release: false
      )
    end
  end

  def emit_deferred_immediately!(chain)
    Array(chain.deferred_result_events).each do |descriptor|
      emit_result_descriptor!(
        chain,
        descriptor.deep_stringify_keys,
        correlate: false,
        route: true,
        release: true
      )
    end
  end

  def emit_result_descriptor!(chain, descriptor, correlate:, route:, release:,
                              attempt: nil, index: nil, changed_at: nil)
    payload = descriptor.fetch('payload', {}).dup
    if correlate
      payload.merge!(
        'operation_id' => chain.id,
        'operation_attempt' => attempt,
        'operation_result_index' => index
      )
    end

    user = ::User.find_by(id: descriptor['user_id']) ||
           VpsAdmin::API::Events.transaction_chain_target_owner(chain) ||
           actor_as_owner(chain)
    vps = ::Vps.find_by(id: descriptor['vps_id'])
    event_args = {}
    event_args[:vpses] = records_by_id(::Vps, descriptor['vps_ids']) if descriptor['vps_ids']

    VpsAdmin::API::Events.emit!(
      descriptor.fetch('event_type'),
      user:,
      vps:,
      source_class: descriptor['source_class'],
      source_id: descriptor['source_id'],
      subject: descriptor['subject'],
      summary: descriptor['summary'],
      payload:,
      severity: descriptor['severity'],
      category: descriptor['category'],
      ip_addr: descriptor['ip_addr'],
      route:,
      release:,
      persist: :always,
      occurred_at: changed_at,
      **event_args
    )
  end

  def result_descriptors(chain)
    chain.transactions.where(handle: Transactions::Utils::NoOp.t_type).order(id: :desc).each do |transaction|
      input = JSON.parse(transaction.input)
      descriptors = input.dig('input', 'result_events')
      return descriptors if descriptors.is_a?(Array)
    rescue JSON::ParserError
      next
    end

    []
  end

  def result_event(chain, index)
    ::Event.where(
      "JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.operation_id')) = ?",
      chain.id.to_s
    ).where(
      "JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.operation_result_index')) = ?",
      index.to_s
    ).order(:id).first
  end

  def owner_from_live_concerns(chain)
    chain.transaction_chain_concerns.order(:id).reverse_each do |concern|
      resolver = CONCERN_OWNER_RESOLVERS[concern.class_name]
      next unless resolver

      klass = concern.class_name.safe_constantize
      next unless klass && klass <= ::ApplicationRecord

      object = klass.find_by(id: concern.row_id)
      next unless object

      owner = resolver.call(object)
      return owner if owner.is_a?(::User)
    rescue ActiveRecord::ActiveRecordError, NoMethodError
      next
    end

    nil
  end

  def actor_as_owner(chain)
    chain.user if chain.user&.role == :user
  end

  def records_by_id(klass, ids)
    records = klass.where(id: ids).index_by(&:id)
    ids.filter_map { |id| records[id.to_i] }
  end
end

VpsAdmin::API::Events.define do
  {
    'operation.started' => ['Operation started', :info],
    'operation.succeeded' => ['Operation succeeded', :info],
    'operation.failed' => ['Operation failed', :error],
    'operation.resolved' => ['Operation failure resolved', :info]
  }.each do |event_name, (label, severity)|
    outcome = event_name.delete_prefix('operation.')
    example_state = {
      'started' => 'queued',
      'succeeded' => 'done',
      'failed' => 'failed',
      'resolved' => 'resolved'
    }.fetch(outcome)
    severity_description = if event_name == 'operation.failed'
                             'Fatal transaction-chain failures use critical severity'
                           end

    event event_name,
          label:,
          category: 'system',
          severity:,
          roles: %i[account admin],
          default_routed: false,
          severity_description:,
          examples: {
            subject: "Start #{outcome}",
            summary: "Operation #123 attempt #1 #{outcome}"
          } do
      fields(
        operation_id: { description: 'Stable transaction-chain operation ID', type: :integer },
        attempt: {
          description: 'One-based execution attempt number',
          type: :integer,
          example: 1
        },
        operation: {
          description: 'Stable operation name',
          type: :string,
          example: 'vps.start'
        },
        operation_label: {
          description: 'User-visible operation label',
          type: :string,
          example: 'Start'
        },
        chain_name: {
          description: 'Persisted transaction chain name',
          type: :string,
          example: 'start'
        },
        chain_type: {
          description: 'Persisted transaction chain type',
          type: :string,
          example: 'TransactionChains::Vps::Start'
        },
        state: {
          description: 'Transaction chain state represented by this event',
          type: :string,
          example: example_state
        },
        successful: {
          description: 'Whether the operation succeeded',
          type: :boolean,
          example: event_name == 'operation.succeeded'
        },
        failed: {
          description: 'Whether the operation failed',
          type: :boolean,
          example: event_name == 'operation.failed'
        },
        concern_type: {
          description: 'How the operation relates to its resources',
          type: :string,
          example: 'affect'
        },
        concern_classes: {
          description: 'Classes of resources affected by the operation',
          type: :string_list,
          example: ['Vps']
        },
        concern_object_ids: { description: 'IDs of resources affected by the operation', type: :integer_list },
        actor_user_id: { description: 'ID of the user who initiated the operation', type: :integer },
        admin_user_id: { description: 'ID of an administrator acting through impersonation', type: :integer },
        user_session_id: { description: 'ID of the session that initiated the operation', type: :integer },
        node_id: { description: 'ID of the node reporting the state', type: :integer },
        node_name: { description: 'Name of the node reporting the state', type: :string },
        producer_event_id: {
          description: 'Stable node-assigned identifier for this state transition',
          type: :string,
          example: '00000000-0000-4000-8000-000000000001'
        },
        changed_at: { description: 'Time when this lifecycle change occurred', type: :datetime }
      )

      if event_name == 'operation.succeeded'
        field(
          :result_event_ids,
          'IDs of completion fact events emitted on success',
          type: :integer_list
        )
      end
    end
  end
end
