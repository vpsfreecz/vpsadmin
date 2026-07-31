require_relative 'base'

module VpsAdmin::Supervisor
  class Node::TransactionChainEvents < Node::Base
    PRODUCER_EVENT_ID_PATTERN = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('transaction_chain_events'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'transaction_chain_events')

      queue.subscribe(manual_ack: true) do |delivery_info, _properties, payload|
        events = JSON.parse(payload).fetch('events')

        ::TransactionChain.transaction(requires_new: true) do
          events.each { |event| process_event(event) }
        end

        @channel.ack(delivery_info.delivery_tag)
      end
    end

    protected

    def process_event(event)
      chain = ::TransactionChain
              .includes(:transaction_chain_concerns, :user)
              .lock
              .find_by(id: event.fetch('chain_id'))
      return unless chain

      producer_event_id = normalize_producer_event_id(event)
      return if event.has_key?('producer_event_id') && producer_event_id.nil?
      return if processed_transition?(chain, producer_event_id)

      ::EventDelivery.abort_unsent_for_transaction_chain!(chain) if aborting_state?(event.fetch('state'))

      VpsAdmin::API::Events.emit_transaction_chain_state!(
        chain,
        previous_state: event['previous_state'],
        state: event.fetch('state'),
        changed_at: event_time(event),
        node:,
        producer_event_id:
      )
      VpsAdmin::API::Events::OperationLifecycle.emit_transition!(
        chain,
        previous_state: event['previous_state'],
        state: event.fetch('state'),
        changed_at: event_time(event),
        node:,
        producer_event_id:
      )
    end

    def normalize_producer_event_id(event)
      value = event['producer_event_id'].to_s
      value if PRODUCER_EVENT_ID_PATTERN.match?(value)
    end

    def processed_transition?(chain, producer_event_id)
      return false if producer_event_id.blank?

      ::Event
        .where(
          event_type: 'transaction_chain.state_changed',
          source_class: ::TransactionChain.name,
          source_id: chain.id
        )
        .where(
          "JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.producer_event_id')) = ?",
          producer_event_id
        )
        .exists?
    end

    def event_time(event)
      return Time.at(event.fetch('time_f')) if event['time_f']
      return Time.at(event.fetch('time')) if event['time']

      nil
    end

    def aborting_state?(state)
      %w[rollbacking failed fatal].include?(state.to_s)
    end
  end
end
