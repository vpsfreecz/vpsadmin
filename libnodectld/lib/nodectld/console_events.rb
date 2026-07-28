require 'json'
require 'securerandom'

module NodeCtld
  module ConsoleEvents
    ROUTING_KEY = 'console_events'.freeze

    module_function

    def publish(action:, vps_id:, client_id:, actor_user_id: nil,
                vps_console_id: nil, reason: nil)
      return unless defined?(NodeCtld::NodeBunny)

      now = Time.now
      producer_event_id = SecureRandom.uuid
      channel = NodeCtld::NodeBunny.create_channel
      exchange = channel.direct(NodeCtld::NodeBunny.exchange_name)
      NodeCtld::NodeBunny.publish_wait(
        exchange,
        JSON.dump(
          producer_event_id:,
          action:,
          vps_id:,
          client_id:,
          actor_user_id:,
          vps_console_id:,
          reason:,
          time: now.to_i,
          time_f: now.to_f
        ),
        routing_key: ROUTING_KEY,
        persistent: true
      )
    ensure
      channel.close if channel && channel.respond_to?(:open?) && channel.open?
    end
  end
end
