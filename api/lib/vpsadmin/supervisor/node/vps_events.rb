require_relative 'base'

module VpsAdmin::Supervisor
  class Node::VpsEvents < Node::Base
    RUNTIME_EVENT_TYPES = %w[
      vps.runtime_halted
      vps.runtime_rebooted
      vps.runtime_oom_stopped
      vps.runtime_oom_restarted
    ].freeze
    PRODUCER_EVENT_ID_PATTERN = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('vps_events'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'vps_events')

      queue.subscribe(manual_ack: true) do |delivery_info, _properties, payload|
        process_event(JSON.parse(payload))
        channel.ack(delivery_info.delivery_tag)
      end
    end

    protected

    def process_event(event)
      ::Event.transaction(requires_new: true) do
        vps = ::Vps.lock.find_by(id: event['id'], node_id: node.id)
        next if vps.nil?

        producer_event_id = normalize_producer_event_id(event)
        next if event.has_key?('producer_event_id') && producer_event_id.nil?
        next if producer_event_id && processed_event?(vps, producer_event_id)

        time = Time.at(event['time'])
        event_payload = { producer_event_id: }.compact

        case event['type']
        when 'exit'
          case event['opts']['exit_type']
          when 'halt'
            vps.log(:halt, time:)

            st = vps.vps_current_status
            st.update!(halted: true) if st
            VpsAdmin::API::Events::VpsLifecycle.emit_runtime!(
              'vps.runtime_halted',
              vps,
              occurred_at: time,
              payload: event_payload
            )
          when 'reboot'
            vps.log(:reboot, time:)
            VpsAdmin::API::Events::VpsLifecycle.emit_runtime!(
              'vps.runtime_rebooted',
              vps,
              occurred_at: time,
              payload: event_payload
            )
          end

        when 'oomd'
          action_past =
            case event['opts']['action']
            when 'restart'
              'restarted'
            when 'stop'
              'stopped'
            else
              raise "Unsupported oomd action #{event['opts']['action'].inspect}"
            end

          vps.log(event['opts']['action'].to_sym, time:)

          incident = ::IncidentReport.create!(
            user: vps.user,
            vps: vps,
            subject: "#{event['opts']['action'].capitalize} due to abuse",
            text: <<~END,
              VPS ##{vps.id} #{vps.hostname} abused shared system resources and was #{action_past}.
            END
            codename: 'oomd',
            detected_at: time
          )

          TransactionChains::IncidentReport::Utils.fire_new(incident)
          VpsAdmin::API::Events::VpsLifecycle.emit_runtime!(
            "vps.runtime_oom_#{action_past}",
            vps,
            occurred_at: time,
            source: incident,
            payload: event_payload.merge(incident_report_id: incident.id)
          )
        end
      end
    end

    def processed_event?(vps, producer_event_id)
      ::Event
        .where(vps:, event_type: RUNTIME_EVENT_TYPES)
        .where(
          "JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.producer_event_id')) = ?",
          producer_event_id
        )
        .exists?
    end

    def normalize_producer_event_id(event)
      value = event['producer_event_id'].to_s
      value if PRODUCER_EVENT_ID_PATTERN.match?(value)
    end
  end
end
