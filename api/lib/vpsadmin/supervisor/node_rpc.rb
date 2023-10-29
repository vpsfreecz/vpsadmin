require 'json'

module VpsAdmin::Supervisor
  class NodeRpc
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(1)

      exchange = @channel.direct('node.rpc')
      queue = @channel.queue('node.rpc', durable: true)

      queue.bind(exchange, routing_key: 'request')

      queue.subscribe(manual_ack: true) do |delivery_info, properties, payload|
        request = Request.new(@channel, exchange, delivery_info, properties)
        request.process(payload)
      end
    end

    protected
    class Request
      def initialize(channel, exchange, delivery_info, properties)
        @channel = channel
        @exchange = exchange
        @delivery_info = delivery_info
        @properties = properties
      end

      def process(payload)
        begin
          req = JSON.parse(payload)
        rescue
          send_error('Unable to parse request as json')
          raise
        end

        handler = Handler.new
        cmd = req['command']

        if !handler.respond_to?(cmd)
          send_error("Command #{cmd.inspect} not found")
          return
        end

        begin
          response = handler.send(
            cmd,
            *req.fetch('args', []),
            **req.fetch('kwargs', {}),
          )
        rescue => e
          send_error("#{e.class}: #{e.message}")
          raise
        else
          send_response(response)
        end

        nil
      end

      protected
      def send_response(response)
        reply({status: true, response: response})
      end

      def send_error(message)
        reply({status: false, message: message})
      end

      def reply(payload)
        @channel.ack(@delivery_info.delivery_tag)

        @exchange.publish(
          payload.to_json,
          persistent: true,
          content_type: 'application/json',
          routing_key: @properties.reply_to,
          correlation_id: @properties.correlation_id,
        )
      end
    end

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

      def list_vps_network_interfaces(node_id)
        ::NetworkInterface
          .select(
            'network_interfaces.id,
            network_interfaces.name,
            vpses.id AS vps_id,
            vpses.user_id AS user_id,
            network_interface_monitors.bytes_in_readout,
            network_interface_monitors.bytes_out_readout,
            network_interface_monitors.packets_in_readout,
            network_interface_monitors.packets_out_readout'
          )
          .joins(:vps)
          .joins('LEFT JOIN network_interface_monitors ON network_interface_monitors.network_interface_id = network_interfaces.id')
          .where(
            vpses: {
              node_id: node_id,
              object_state: 'active',
            },
          ).map do |netif|
          {
            id: netif.id,
            name: netif.name,
            vps_id: netif.vps_id,
            user_id: netif.user_id,
            bytes_in_readout: netif.bytes_in_readout,
            bytes_out_readout: netif.bytes_out_readout,
            packets_in_readout: netif.bytes_in_readout,
            packets_out_readout: netif.bytes_out_readout,
          }
        end
      end

      def find_vps_network_interface(vps_id, vps_name)
        netif =
          ::NetworkInterface
            .select(
              'network_interfaces.id,
              network_interfaces.name,
              vpses.id AS vps_id,
              vpses.user_id AS user_id,
              network_interface_monitors.bytes_in_readout,
              network_interface_monitors.bytes_out_readout,
              network_interface_monitors.packets_in_readout,
              network_interface_monitors.packets_out_readout'
            )
            .joins(:vps)
            .joins('LEFT JOIN network_interface_monitors ON network_interface_monitors.network_interface_id = network_interfaces.id')
            .where(vps_id: vps_id, name: vps_name).take

        return if netif.nil?

        {
          id: netif.id,
          name: netif.name,
          vps_id: netif.vps_id,
          user_id: netif.user_id,
          bytes_in_readout: netif.bytes_in_readout,
          bytes_out_readout: netif.bytes_out_readout,
          packets_in_readout: netif.bytes_in_readout,
          packets_out_readout: netif.bytes_out_readout,
        }
      end

      def list_running_vps_ids(node_id)
        ::Vps.select('vpses.id').joins(:vps_current_status).where(
          vpses: {node_id: node_id, object_state: 'active'},
          vps_current_statuses: {is_running: true},
        ).map(&:id)
      end
    end
  end
end
