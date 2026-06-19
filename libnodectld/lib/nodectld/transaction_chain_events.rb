require 'json'

module NodeCtld
  module TransactionChainEvents
    STATES = {
      0 => 'staged',
      1 => 'queued',
      2 => 'done',
      3 => 'rollbacking',
      4 => 'failed',
      5 => 'fatal',
      6 => 'resolved'
    }.freeze

    ROUTING_KEY = 'transaction_chain_events'.freeze

    module_function

    def state_name(state)
      STATES.fetch(state.to_i, state.to_s)
    end

    def publish(chain_id:, previous_state:, state:)
      return unless defined?(NodeCtld::NodeBunny)

      now = Time.now
      channel = NodeCtld::NodeBunny.create_channel
      exchange = channel.direct(NodeCtld::NodeBunny.exchange_name)
      NodeCtld::NodeBunny.publish_drop(
        exchange,
        JSON.dump(
          events: [
            {
              chain_id:,
              previous_state: state_name(previous_state),
              state: state_name(state),
              time: now.to_i,
              time_f: now.to_f
            }
          ]
        ),
        routing_key: ROUTING_KEY,
        persistent: true
      )
    ensure
      channel.close if channel && channel.respond_to?(:open?) && channel.open?
    end
  end
end
