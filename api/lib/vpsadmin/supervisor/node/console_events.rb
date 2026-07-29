require_relative 'base'

module VpsAdmin::Supervisor
  class Node::ConsoleEvents < Node::Base
    ACTIONS = %w[opened closed].freeze
    CLOSE_REASONS = VpsAdmin::API::Events::VpsConsole::CLOSE_REASONS
    EVENT_TYPES = ACTIONS.map { |action| "vps.console_#{action}" }.freeze
    PRODUCER_EVENT_ID_PATTERN = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('console_events'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'console_events')

      queue.subscribe(manual_ack: true) do |delivery_info, _properties, payload|
        process_event(JSON.parse(payload))
        channel.ack(delivery_info.delivery_tag)
      end
    end

    protected

    def process_event(message)
      action = message['action'].to_s
      return unless ACTIONS.include?(action)

      client_id = message['client_id'].to_s
      return unless /\A[0-9a-f]{32}\z/.match?(client_id)

      producer_event_id = normalize_producer_event_id(message)
      return if message.has_key?('producer_event_id') && producer_event_id.nil?

      vps = ::Vps.find_by(id: message['vps_id'], node_id: node.id)
      return if vps.nil?

      close_reason =
        if action == 'closed' && CLOSE_REASONS.include?(message['reason'])
          message['reason']
        end

      vps.with_lock do
        next if producer_event_id && producer_event_persisted?(vps, producer_event_id)

        VpsAdmin::API::Events.emit!(
          "vps.console_#{action}",
          user: vps.user,
          vps:,
          source: node,
          subject: "VPS ##{vps.id} console #{action}",
          summary: "Remote console client #{action} on #{node.domain_name}",
          payload: {
            vps_id: vps.id,
            vps_hostname: vps.hostname,
            node_id: node.id,
            node_name: node.domain_name,
            console_client_id: client_id,
            producer_event_id:,
            actor_user_id: positive_id(message['actor_user_id']),
            vps_console_id: positive_id(message['vps_console_id']),
            close_reason:
          }.compact,
          occurred_at: event_time(message)
        )
      end
    end

    def normalize_producer_event_id(message)
      value = message['producer_event_id'].to_s
      value if PRODUCER_EVENT_ID_PATTERN.match?(value)
    end

    def producer_event_persisted?(vps, producer_event_id)
      ::Event
        .where(
          event_type: EVENT_TYPES,
          vps:,
          source_class: node.class.name,
          source_id: node.id
        )
        .where(
          "JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.producer_event_id')) = ?",
          producer_event_id
        )
        .exists?
    end

    def event_time(message)
      return Time.at(message.fetch('time_f')) if message['time_f']
      return Time.at(message.fetch('time')) if message['time']

      Time.now
    end

    def positive_id(value)
      id = Integer(value, exception: false)
      id if id&.positive?
    end
  end
end
