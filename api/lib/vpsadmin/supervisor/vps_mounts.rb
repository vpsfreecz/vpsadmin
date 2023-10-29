module VpsAdmin::Supervisor
  class VpsMounts
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(1)

      exchange = @channel.direct('node.vps_mounts')
      queue = @channel.queue('node.vps_mounts', durable: true)

      queue.bind(exchange)

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
