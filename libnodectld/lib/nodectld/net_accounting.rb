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
        remove_netif
        remove_vps
        netif_up
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
    end

    def init(db)
      @netifs = fetch_netifs(db)
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
    # @param netif_id [Integer]
    # @param vps_name [String]
    def add_netif(vps_id, netif_id, vps_name)
      log(:info, "Registering interface in VPS #{vps_id} id=#{netif_id} name=#{vps_name}")

      @mutex.synchronize do
        @netifs << NetAccounting::Interface.new(
          vps_id,
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
      log(:info, "Removing interface from VPS #{vps_id} id=#{netif_id} name=#{vps_name}")

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

    # A new interface has come online, make sure it is accounted
    # @param vps_id [Integer]
    # @param vps_name [String]
    def netif_up(vps_id, vps_name)
      @discovery_queue << [:up, vps_id, vps_name]
      nil
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

    def fetch_netifs(db)
      rs = db.query(
        "SELECT
          vpses.id AS vps_id, netifs.id AS netif_id, netifs.name,
          m.bytes_in_readout, m.bytes_out_readout,
          m.packets_in_readout, m.packets_out_readout
        FROM network_interfaces netifs
        INNER JOIN vpses ON netifs.vps_id = vpses.id
        LEFT JOIN network_interface_monitors m ON m.network_interface_id = netifs.id
        WHERE
          vpses.node_id = #{$CFG.get(:vpsadmin, :node_id)}
          AND vpses.object_state = 0"
      )

      ret = []

      rs.each do |row|
        ret << NetAccounting::Interface.new(
          row['vps_id'],
          row['netif_id'],
          row['name'],
          bytes_in: row['bytes_in_readout'] || 0,
          bytes_out: row['bytes_out_readout'] || 0,
          packets_in: row['packets_in_readout'] || 0,
          packets_out: row['packets_out_readout'] || 0,
        )
      end

      ret
    end

    def fetch_netif(vps_id, vps_name)
      db = NodeCtld::Db.new

      # It is important to not check vpses.node_id, because this method may be
      # called as part of a VPS migration, where database changes are not yet
      # confirmed and vpses.node_id points to the source node.
      rs = db.prepared(
        "SELECT
          vpses.id AS vps_id, netifs.id AS netif_id, netifs.name,
          m.bytes_in_readout, m.bytes_out_readout,
          m.packets_in_readout, m.packets_out_readout
        FROM network_interfaces netifs
        INNER JOIN vpses ON netifs.vps_id = vpses.id
        LEFT JOIN network_interface_monitors m ON m.network_interface_id = netifs.id
        WHERE vpses.id = ? AND netifs.name = ?",
        vps_id,
        vps_name
      )

      row = rs.get
      return if row.nil?

      netif = NetAccounting::Interface.new(
        row['vps_id'],
        row['netif_id'],
        row['name'],
        bytes_in: row['bytes_in_readout'] || 0,
        bytes_out: row['bytes_out_readout'] || 0,
        packets_in: row['packets_in_readout'] || 0,
        packets_out: row['packets_out_readout'] || 0,
      )

      db.close
      netif
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

      db = NodeCtld::Db.new
      log_interval = $CFG.get(:traffic_accounting, :log_interval)

      @mutex.synchronize do
        @netifs.each do |netif|
          netif.save(db, log_interval) if netif.changed?
        end
      end

      db.close
    end
  end
end
