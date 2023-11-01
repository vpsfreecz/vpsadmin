require 'libosctl'
require 'singleton'

module NodeCtld
  class NetAccounting
    include Singleton
    include OsCtl::Lib::Utils::Log

    class << self
      %i(
        init
        update
        stop
        add_netif
        rename_netif
        remove_netif
        remove_vps
        chown_vps
        netif_up
        dump
      ).each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      @netifs = []
      @update_queue = OsCtl::Lib::Queue.new
      @discovery_queue = OsCtl::Lib::Queue.new
      @mutex = Mutex.new
      @channel = NodeBunny.create_channel
      @monitor_exchange = @channel.direct('node:net_monitor')
      @accounting_exchange = @channel.direct('node:net_accounting')
    end

    def init
      @netifs = fetch_netifs
      log(:info, "Accounting #{@netifs.length} network interfaces")

      @update_thread = Thread.new { run_reader }
      @discovery_thread = Thread.new { run_discovery }
    end

    # Trigger on-demand accounting update
    def update
      @update_queue << :update
    end

    # Stop traffic accounting
    def stop
      if @update_thread
        @update_queue << :stop
        @update_thread.join
        @update_thread = nil
      end

      if @discovery_thread
        @discovery_queue << :stop
        @discovery_thread.join
        @discovery_thread = nil
      end
    end

    # Register a new network interface
    # @param vps_id [Integer]
    # @param user_id [Integer]
    # @param netif_id [Integer]
    # @param vps_name [String]
    def add_netif(vps_id, user_id, netif_id, vps_name)
      log(:info, "Registering interface in VPS #{vps_id} id=#{netif_id} name=#{vps_name}")

      @mutex.synchronize do
        @netifs << NetAccounting::Interface.new(
          vps_id,
          user_id,
          netif_id,
          vps_name,
        )
      end

      nil
    end

    # Rename an existing network interface
    # @param vps_id [Integer]
    # @param netif_id [Integer]
    # @param new_vps_name [String]
    def rename_netif(vps_id, netif_id, new_vps_name)
      log(:info, "Renaming interface in VPS #{vps_id} id=#{netif_id} name->#{new_vps_name}")

      @mutex.synchronize do
        n = @netifs.detect do |netif|
          netif.vps_id == vps_id && netif.id == netif_id
        end
        next if n.nil?

        n.vps_name = new_vps_name
      end

      nil
    end

    # Unregister a network interface
    # @param vps_id [Integer]
    # @param netif_id [Integer]
    def remove_netif(vps_id, netif_id)
      log(:info, "Removing interface from VPS #{vps_id} id=#{netif_id}")

      @mutex.synchronize do
        @netifs.delete_if do |netif|
          netif.vps_id == vps_id && netif.id == netif_id
        end
      end

      nil
    end

    # Unregister all network interfaces for a VPS
    # @param vps_id [Integer]
    def remove_vps(vps_id)
      log(:info, "Removing interfaces of VPS #{vps_id}")

      @mutex.synchronize do
        @netifs.delete_if do |netif|
          netif.vps_id == vps_id
        end
      end

      nil
    end

    # Update user ID on VPS interfaces
    # @param vps_id [Integer]
    # @param user_id [Integer]
    def chown_vps(vps_id, user_id)
      log(:info, "Chowning interfaces of VPS #{vps_id} to user_id=#{user_id}")

      @mutex.synchronize do
        @netifs.each do |netif|
          netif.user_id = user_id
        end
      end

      nil
    end

    # A new interface has come online, make sure it is accounted
    # @param vps_id [Integer]
    # @param vps_name [String]
    def netif_up(vps_id, vps_name)
      @discovery_queue << [:up, vps_id, vps_name]
      nil
    end

    # Export a list of accounted interfaces
    # @return [Array]
    def dump
      @mutex.synchronize do
        @netifs.map(&:dump)
      end
    end

    def log_type
      'net-accounting'
    end

    protected
    def run_reader
      loop do
        v = @update_queue.pop(timeout: $CFG.get(:traffic_accounting, :update_interval))
        return if v == :stop

        update_netifs if $CFG.get(:traffic_accounting, :enable)
      end
    end

    def run_discovery
      loop do
        v = @discovery_queue.pop
        return if v == :stop

        cmd, *args = v

        case cmd
        when :up
          vps_id, vps_name = args
          discover_netif(vps_id, vps_name)
        end
      end
    end

    def fetch_netifs
      ret = []

      RpcClient.run do |rpc|
        rpc.list_vps_network_interfaces.each do |netif|
          ret << NetAccounting::Interface.new(
            netif['vps_id'],
            netif['user_id'],
            netif['id'],
            netif['name'],
            bytes_in: netif['bytes_in_readout'] || 0,
            bytes_out: netif['bytes_out_readout'] || 0,
            packets_in: netif['packets_in_readout'] || 0,
            packets_out: netif['packets_out_readout'] || 0,
          )
        end
      end

      ret
    end

    def fetch_netif(vps_id, vps_name)
      netif =
        RpcClient.run do |rpc|
          rpc.find_vps_network_interface(vps_id, vps_name)
        end

      return if netif.nil?

      NetAccounting::Interface.new(
        netif['vps_id'],
        netif['user_id'],
        netif['id'],
        netif['name'],
        bytes_in: netif['bytes_in_readout'] || 0,
        bytes_out: netif['bytes_out_readout'] || 0,
        packets_in: netif['packets_in_readout'] || 0,
        packets_out: netif['packets_out_readout'] || 0,
      )
    end

    def discover_netif(vps_id, vps_name)
      fetch = false

      @mutex.synchronize do
        n = @netifs.detect do |netif|
          netif.vps_id == vps_id && netif.vps_name == vps_name
        end

        fetch = true if n.nil?
      end

      return unless fetch

      netif = fetch_netif(vps_id, vps_name)
      return if netif.nil?

      log(:info, "Discovered netif in VPS #{netif.vps_id}: id=#{netif.id} name=#{netif.vps_name}")

      @mutex.synchronize do
        @netifs << netif
      end
    end

    def update_netifs
      changed = false

      @mutex.synchronize do
        @netifs.each do |netif|
          host_name = VethMap.get(netif.vps_id, netif.vps_name)
          next if host_name.nil?

          netif.update(host_name)
          changed = true
        end
      end

      return unless changed

      monitors = []
      accountings = []

      log_interval = $CFG.get(:traffic_accounting, :log_interval)
      max_size = $CFG.get(:traffic_accounting, :batch_size)

      @mutex.synchronize do
        @netifs.each do |netif|
          next unless netif.changed?

          monitors << netif.export_monitor

          if netif.export_accounting?(log_interval)
            accountings << netif.export_accounting
          end

          send_data(@monitor_exchange, :monitors, monitors, max_size)
          send_data(@accounting_exchange, :accounting, accountings, max_size)
        end

        send_data(@monitor_exchange, :monitors, monitors)
        send_data(@accounting_exchange, :accounting, accountings)
      end
    end

    def send_data(exchange, key, to_save, max_size = 0)
      return if to_save.length <= max_size

      exchange.publish(
        {key => to_save}.to_json,
        content_type: 'application/json',
        routing_key: $CFG.get(:vpsadmin, :routing_key),
      )

      to_save.clear
    end
  end
end
