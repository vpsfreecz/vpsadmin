require_relative 'base'

module VpsAdmin::Supervisor
  class Node::VpsMounts < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('vps_mounts'),
        durable: true,
        arguments: {'x-queue-type' => 'quorum'},
      )

      queue.bind(exchange, routing_key: 'vps_mounts')

      queue.subscribe(manual_ack: true) do |delivery_info, _properties, payload|
        state = JSON.parse(payload)
        update_mount_state(state)
        @channel.ack(delivery_info.delivery_tag)
      end
    end

    protected
    def update_mount_state(state)
      q =
        if state['id'] == 'all'
          ::Mount.where(vps_id: state['vps_id'])
        else
          ::Mount.where(id: state['id'])
        end

      q.update_all(current_state: state['state'], updated_at: Time.at(state['time']))
    end
  end
end
