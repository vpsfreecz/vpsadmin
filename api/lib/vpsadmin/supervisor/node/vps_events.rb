require_relative 'base'

module VpsAdmin::Supervisor
  class Node::VpsEvents < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('vps_events'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'vps_events')

      queue.subscribe do |_delivery_info, _properties, payload|
        process_event(JSON.parse(payload))
      end
    end

    protected

    def process_event(event)
      vps = ::Vps.find(event['id'])
      return if vps.nil?

      time = Time.at(event['time'])

      case event['type']
      when 'exit'
        case event['opts']['exit_type']
        when 'halt'
          vps.log(:halt, time:)

          st = vps.vps_current_status
          st.update!(halted: true) if st
        when 'reboot'
          vps.log(:reboot, time:)
        end
      end
    end
  end
end
