require 'json'

module VpsAdmin::Supervisor
  class NodeRpc
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(1)

      exchange = @channel.direct('node.rpc')
      queue = @channel.queue('node.rpc')

      queue.bind(exchange, routing_key: 'request')

      queue.subscribe(manual_ack: true) do |delivery_info, properties, payload|
        cmd = JSON.parse(payload)
        handler = Handler.new

        response = handler.send(
          cmd.fetch('command'),
          *cmd.fetch('args', []),
          **cmd.fetch('kwargs', {}),
        )

        @channel.ack(delivery_info.delivery_tag)

        exchange.publish(
          {response: response}.to_json,
          content_type: 'application/json',
          routing_key: properties.reply_to,
          correlation_id: properties.correlation_id,
        )
      end
    end

    protected
    class Handler
      def list_pools(node_id)
        ::Pool.where(node_id: node_id).map do |pool|
          {id: pool.id, filesystem: pool.filesystem}
        end
      end

      def list_vps_status_check(node_id)
        ::Vps.where(
          node_id: node_id,
          object_state: %w(active suspended),
          confirmed: ::Vps.confirmed(:confirmed),
        ).map do |vps|
          {id: vps.id, read_hostname: !vps.manage_hostname}
        end
      end
    end
  end
end
