module VpsAdmin::Supervisor
  class PoolStatus
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(1)

      exchange = @channel.direct('node.pool_statuses')
      queue = @channel.queue('node.pool_statuses')

      queue.bind(exchange)

      queue.subscribe do |_delivery_info, _properties, payload|
        status = JSON.parse(payload)

        ::Pool.where(id: status['id']).update_all(
          state: status['state'],
          scan: status['scan'],
          scan_percent: status['scan_percent'],
          checked_at: Time.at(status['time']),
        )
      end
    end
  end
end
