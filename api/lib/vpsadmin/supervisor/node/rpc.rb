require_relative 'base'

module VpsAdmin::Supervisor
  class Node::Rpc < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('rpc'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'rpc')

      queue.subscribe(manual_ack: true) do |delivery_info, properties, payload|
        request = Request.new(@channel, exchange, delivery_info, properties, node)
        request.process(payload)
      end
    end

    class Request
      def initialize(channel, exchange, delivery_info, properties, node)
        @channel = channel
        @exchange = exchange
        @delivery_info = delivery_info
        @properties = properties
        @node = node
      end

      def process(payload)
        begin
          req = JSON.parse(payload)
        rescue StandardError
          send_error('Unable to parse request as json')
          raise
        end

        handler = Handler.new(@node)
        cmd = req['command']

        unless handler.respond_to?(cmd)
          send_error("Command #{cmd.inspect} not found")
          return
        end

        begin
          response = handler.send(
            cmd,
            *req.fetch('args', []),
            **symbolize_hash_keys(req.fetch('kwargs', {}))
          )
        rescue ActiveRecord::AdapterError => e
          send_error("#{e.class}: #{e.message}", retry: true)
          raise
        rescue StandardError => e
          send_error("#{e.class}: #{e.message}")
          raise
        else
          send_response(response)
        end

        nil
      end

      protected

      def send_response(response)
        reply({ status: true, response: })
      end

      def send_error(message, retry: false)
        reply({ status: false, message:, retry: })
      end

      def reply(payload)
        @channel.ack(@delivery_info.delivery_tag)

        begin
          @exchange.publish(
            payload.to_json,
            persistent: true,
            content_type: 'application/json',
            routing_key: @properties.reply_to,
            correlation_id: @properties.correlation_id
          )
        rescue Bunny::ConnectionClosedError
          warn 'Node::Rpc#reply: connection closed, retry in 5s'
          sleep(5)
          retry
        end
      end

      def symbolize_hash_keys(hash)
        hash.transform_keys(&:to_sym)
      end
    end

    class Handler
      def initialize(node)
        @node = node
      end

      def get_node_config
        node = ::Node
               .select('name, role, ip_addr, max_tx, max_rx')
               .where(id: @node.id).take
        return if node.nil?

        {
          role: node.role,
          ip_addr: node.ip_addr,
          max_tx: node.max_tx,
          max_rx: node.max_rx
        }
      end

      def list_pools
        ::Pool.where(node: @node).map do |pool|
          {
            id: pool.id,
            name: pool.filesystem.split('/').first,
            filesystem: pool.filesystem,
            role: pool.role,
            refquota_check: pool.refquota_check
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
            datasets.vps_id,
            dataset_properties.name AS property_name,
            dataset_properties.id AS property_id'
          )
          .joins(:dataset, :dataset_properties, :pool)
          .where(
            dataset_in_pools: {
              pool_id:,
              confirmed: ::DatasetInPool.confirmed(:confirmed)
            },
            pools: {
              node_id: @node.id
            },
            dataset_properties: {
              name: properties
            }
          ).map do |dip|
            {
              dataset_in_pool_id: dip.id,
              dataset_id: dip.dataset_id,
              dataset_name: dip.full_name,
              property_id: dip.property_id,
              property_name: dip.property_name,
              vps_id: dip.vps_id
            }
          end
      end

      def list_vps_status_check
        ::Vps.where(
          node: @node,
          object_state: %w[active suspended],
          confirmed: ::Vps.confirmed(:confirmed)
        ).map do |vps|
          {
            id: vps.id,
            read_hostname: !vps.manage_hostname,
            pool_fs: vps.dataset_in_pool.pool.filesystem
          }
        end
      end

      def list_vps_network_interfaces
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
              node_id: @node.id,
              object_state: 'active'
            }
          ).map do |netif|
          {
            id: netif.id,
            name: netif.name,
            vps_id: netif.vps_id,
            user_id: netif.user_id,
            bytes_in_readout: netif.bytes_in_readout,
            bytes_out_readout: netif.bytes_out_readout,
            packets_in_readout: netif.bytes_in_readout,
            packets_out_readout: netif.bytes_out_readout
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
          .where(
            vps_id:,
            name: vps_name
          ).take

        return if netif.nil?

        {
          id: netif.id,
          name: netif.name,
          vps_id: netif.vps_id,
          user_id: netif.user_id,
          bytes_in_readout: netif.bytes_in_readout,
          bytes_out_readout: netif.bytes_out_readout,
          packets_in_readout: netif.bytes_in_readout,
          packets_out_readout: netif.bytes_out_readout
        }
      end

      def list_running_vps_ids
        ::Vps.select('vpses.id').joins(:vps_current_status).where(
          vpses: { node_id: @node.id, object_state: 'active' },
          vps_current_statuses: { is_running: true }
        ).map(&:id)
      end

      def list_vps_user_namespace_maps(pool_id, limit:, from_id: nil)
        q = ::Vps
            .joins(:dataset_in_pool)
            .includes(user_namespace_map: :user_namespace_map_entries)
            .where(
              object_state: %w[active suspended soft_delete],
              confirmed: ::Vps.confirmed(:confirmed),
              node: @node,
              dataset_in_pools: { pool_id: }
            )
            .limit(limit)

        q = q.where('vpses.id > ?', from_id) if from_id

        q.map do |vps|
          {
            vps_id: vps.id,
            map_name: vps.user_namespace_map_id.to_s,
            uidmap: vps.user_namespace_map.build_map(:uid),
            gidmap: vps.user_namespace_map.build_map(:gid)
          }
        end
      end

      # @param from_id [Integer, nil]
      # @param limit [Integer]
      # @return [Array<Hash>]
      def list_exports(limit:, from_id: nil)
        q = ::Export
            .joins(dataset_in_pool: :pool)
            .includes(
              :host_ip_addresses,
              :snapshot_in_pool_clone,
              dataset_in_pool: %i[pool dataset],
              network_interface: { ip_addresses: :host_ip_addresses },
              export_hosts: :ip_address
            )
            .where(
              pools: { node_id: @node.id }
            )
            .limit(limit)

        q = q.where('exports.id > ?', from_id) if from_id

        q.map do |ex|
          {
            id: ex.id,
            pool_fs: ex.dataset_in_pool.pool.filesystem,
            dataset_name: ex.dataset_in_pool.dataset.full_name,
            clone_name: ex.snapshot_in_pool_clone && ex.snapshot_in_pool_clone.name,
            path: ex.path,
            threads: ex.threads,
            enabled: ex.enabled,
            ip_address: ex.network_interface.ip_addresses.first.host_ip_addresses.first.ip_addr,
            hosts: ex.export_hosts.map do |host|
              {
                ip_address: host.ip_address.ip_addr,
                prefix: host.ip_address.prefix,
                fsid: ex.fsid,
                rw: host.rw,
                sync: host.sync,
                subtree_check: host.subtree_check,
                root_squash: host.root_squash
              }
            end
          }
        end
      end

      # @param token [String]
      # @return [Integer, nil] VPS id
      def authenticate_console_session(token)
        console = ::VpsConsole
                  .select('vps_id')
                  .joins(:vps)
                  .where(token:, vpses: { node_id: @node.id })
                  .where('expiration > ?', Time.now)
                  .take

        console && console.vps_id
      end
    end
  end
end
