require_relative 'base'

module VpsAdmin::Supervisor
  class Node::TransactionChainEvents < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('transaction_chain_events'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'transaction_chain_events')

      queue.subscribe do |_delivery_info, _properties, payload|
        events = JSON.parse(payload).fetch('events')
        events.each { |event| process_event(event) }
      end
    end

    protected

    def process_event(event)
      chain = ::TransactionChain
              .includes(:transaction_chain_concerns, :user)
              .find_by(id: event.fetch('chain_id'))
      return unless chain

      ::EventDelivery.abort_unsent_for_transaction_chain!(chain) if aborting_state?(event.fetch('state'))

      VpsAdmin::API::Events.emit_transaction_chain_state!(
        chain,
        previous_state: event['previous_state'],
        state: event.fetch('state'),
        changed_at: event_time(event),
        node:
      )
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
