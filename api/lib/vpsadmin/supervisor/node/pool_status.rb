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
        status = JSON.parse(payload)

        ::Pool.where(id: status['id'], node_id: node.id).update_all(
          state: status['state'],
          scan: status['scan'],
          scan_percent: status['scan_percent'],
          checked_at: Time.at(status['time'])
        )
      end
    end
  end
end
