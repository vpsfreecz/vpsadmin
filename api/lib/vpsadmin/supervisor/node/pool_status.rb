require_relative 'base'

module VpsAdmin::Supervisor
  class Node::PoolStatus < Node::Base
    def start
      exchange = channel.direct('node:pool_statuses')
      queue = channel.queue(queue_name('pool_statuses'))

      queue.bind(exchange, routing_key: node.routing_key)

      queue.subscribe do |_delivery_info, _properties, payload|
        status = JSON.parse(payload)

        ::Pool.where(id: status['id'], node_id: node.id).update_all(
          state: status['state'],
          scan: status['scan'],
          scan_percent: status['scan_percent'],
          checked_at: Time.at(status['time']),
        )
      end
    end
  end
end
