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
          {
            id: pool.id,
            name: pool.filesystem.split('/').first,
            filesystem: pool.filesystem,
            role: pool.role,
            refquota_check: pool.refquota_check,
          }
        end
      end

      # @param pool_id [Integer]
      # @param properties [Array<String>]
      # @return [Array<Hash>]
      def list_pool_dataset_properties(pool_id, properties)
        ::DatasetInPool
          .select(
            'dataset_in_pools.id,
            dataset_in_pools.dataset_id,
            datasets.full_name,
            dataset_properties.name AS property_name,
            dataset_properties.id AS property_id'
          )
          .joins(:dataset, :dataset_properties)
          .where(
            dataset_in_pools: {
              pool_id: pool_id,
              confirmed: ::DatasetInPool.confirmed(:confirmed),
            },
            dataset_properties: {
              name: properties,
            },
          ).map do |dip|
            {
              dataset_in_pool_id: dip.id,
              dataset_id: dip.dataset_id,
              dataset_name: dip.full_name,
              property_id: dip.property_id,
              property_name: dip.property_name,
            }
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
