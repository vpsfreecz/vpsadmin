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

    # The existing node protocol is the only trusted source for this rule.
    def self.record_oomd_event(vps, node:, action:, time:, now: Time.now.utc)
      key = Digest::SHA256.hexdigest([node.id, vps.id, 'oomd', time.to_i, action].join(':'))
      ::IncidentEscalation.ingest!(vps, incident_type: 'oomd', source_node: node, now:, attributes: {
                                    codename: 'oomd', detected_at: time,
                                    subject: "#{action.capitalize} due to abuse",
                                    text: "VPS ##{vps.id} #{vps.hostname} abused shared system resources and was #{action == 'stop' ? 'stopped' : 'restarted'}.\n",
                                    source_key: key, source_kind: 'node_vps_event', source_node_id: node.id, source_action: action
                                  }) { vps.log(action.to_sym, time:) }
    end

    protected

    def process_event(event)
      vps = ::Vps.find_by(id: event['id'], node_id: node.id)
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

      when 'oomd'
        action = event['opts']['action']
        unless %w[restart stop].include?(action)
          raise "Unsupported oomd action #{action.inspect}"
        end

        self.class.record_oomd_event(vps, node:, action:, time:)
      end
    end
  end
end
