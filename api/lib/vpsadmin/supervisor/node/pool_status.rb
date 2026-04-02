require_relative 'base'

module VpsAdmin::Supervisor
  class Node::PoolStatus < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('pool_statuses'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'pool_statuses')

      queue.subscribe do |_delivery_info, _properties, payload|
        update_pool_status(JSON.parse(payload))
      end
    end

    protected

    def update_pool_status(status)
      ::Pool.where(id: status['id'], node_id: node.id).update_all(
        state: status['state'],
        scan: status['scan'],
        scan_percent: status['scan_percent'],
        checked_at: Time.at(status['time']),
        total_space: save_value(status, 'total_bytes'),
        used_space: save_value(status, 'used_bytes'),
        available_space: save_value(status, 'available_bytes')
      )
    end

    def save_value(status, key)
      return nil unless %w[total_bytes used_bytes available_bytes].all? { |v| status.has_key?(v) }

      value = status[key]
      return nil if value.nil?

      (value / 1024.0 / 1024).round
    end
  end
end
