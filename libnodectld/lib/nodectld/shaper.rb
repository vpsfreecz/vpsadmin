require 'libosctl'
require 'nodectld/db'
require 'nodectld/utils'
require 'singleton'
require 'thread'

module NodeCtld
  # {Shaper} configures network interfaces to limit TX/RX per VPS IP address
  #
  # The shaper is configured on all network interfaces on the host that VPS
  # IP addresses are routed through. The shaper is also set on every per-VPS
  # veth interface.
  #
  # On nodectld start:
  #   - configure host interfaces for all IP addresses
  #   - configure IP addresses on VPS veth interfaces of running VPS
  #
  # On VPS start:
  #   - configure IP addresses on VPS veth interface
  #
  # On IP add/del:
  #   - configure both host and VPS interfaces
  class Shaper
    include Singleton
    include OsCtl::Lib::Utils::Log
    include Utils::System

    class << self
      # Initialize the shaper on all available interfaces
      # @param db [Db]
      def init(db)
        instance.init(db)
      end

      # Configure shaper on the per-VPS veth interface
      # @param vps_id [Integer]
      # @param host_veth [String] VPS veth interface name on the host
      # @param ct_veth [String] VPS veth interface name in the VPS
      def setup_vps_veth(vps_id, host_veth, ct_veth)
        instance.setup_vps_veth(vps_id, host_veth, ct_veth)
      end

      # Configure shaper for a new IP address on all interfaces
      # @param vps_id [Integer]
      # @param opts [Hash]
      # @option opts [String] :netif VPS interface name
      # @option opts [String] :addr
      # @option opts [Integer] :prefix
      # @option opts [Integer] :version
      # @option opts [Integer] :class_id
      # @option opts [Integer] :max_tx bytes per second
      # @option opts [Integer] :max_rx bytes per second
      def add_ip(vps_id, opts)
        instance.add_ip(vps_id, opts)
      end

      # Remove shaper for an IP address from all interfaces
      # @param vps_id [Integer]
      # @param opts [Hash]
      # @option opts [String] :netif VPS interface name
      # @option opts [String] :addr
      # @option opts [Integer] :prefix
      # @option opts [Integer] :version
      # @option opts [Integer] :class_id
      def remove_ip(vps_id, opts)
        instance.remove_ip(vps_id, opts)
      end

      # Reconfigure shaper of an IP address on all interfaces
      # @param vps_id [Integer]
      # @param opts [Hash]
      # @option opts [String] :netif VPS interface name
      # @option opts [String] :addr
      # @option opts [Integer] :prefix
      # @option opts [Integer] :version
      # @option opts [Integer] :class_id
      # @option opts [Integer] :max_tx bytes per second
      # @option opts [Integer] :max_rx bytes per second
      def update_ip(vps_id, opts)
        instance.update_ip(vps_id, opts)
      end

      # Reconfigure maximum tx/rx bandwidth for all interfaces
      # @param tx [Integer] bytes per second
      # @param rx [Integer] bytes per second
      def update_root(tx, rx)
        instance.update_root(tx, rx)
      end

      # Reset shaper on all interfaces
      def flush
        instance.flush
      end

      # Reinitialize shaper on all interfaces
      # @param db [Db]
      def reinit(db)
        instance.reinit(db)
      end
    end

    def initialize
      @mutex = Mutex.new
    end

    def init(db)
      sync do
        safe_init(db)
      end
    end

    def setup_vps_veth(vps_id, vps_host_veth, vps_ct_veth)
      sync do
        tx = $CFG.get(:vpsadmin, :max_tx)
        rx = $CFG.get(:vpsadmin, :max_rx)

        vps = get_vps(Db.new, vps_id)

        if vps.netif != vps_ct_veth
          log(:warn, "Unknown veth #{vps_ct_veth} for VPS #{vps_id}")
          next
        end

        tc("qdisc add dev #{vps_host_veth} root handle 1: htb", [2])
        tc("class add dev #{vps_host_veth} parent 1: classid 1:1 htb "+
           "rate #{rx}bps ceil #{rx}bps burst 1M", [2])

        vps.ips.each do |ip|
          # Host net interfaces are already setup, so all that needs to be
          # configured is the VPS veth interface

          tc("class add dev #{vps_host_veth} parent 1:1 classid 1:#{ip.class_id} "+
             "htb rate #{ip.max_rx}bps ceil #{ip.max_rx}bps burst 300k", [2])

          add_filters([vps_host_veth], 'dst', [ip])

          tc("qdisc add dev #{vps_host_veth} parent 1:#{ip.class_id} "+
              "handle #{ip.class_id}: sfq perturb 10", [2])
        end
      end
    end

    def add_ip(vps_id, opts)
      vps = VpsInfo.new(vps_id, opts[:netif], [])

      ip = IpInfo.new(
        opts[:addr],
        opts[:prefix],
        opts[:version],
        opts[:class_id],
        opts[:max_tx],
        opts[:max_rx],
      )

      vps_host_veth = VethMap[vps.id][vps.netif]

      sync do
        shape_ips(vps, vps_host_veth, [ip])
      end
    end

    def remove_ip(vps_id, opts)
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)
      vps_host_veth = VethMap[vps_id][opts[:netif]]

      sync do
        host_netifs.each do |netif|
          tc("qdisc del dev #{netif} parent 1:#{opts[:class_id]} "+
             "handle #{opts[:class_id]}:", [2])
        end

        if vps_host_veth
          tc("qdisc del dev #{vps_host_veth} parent 1:#{opts[:class_id]} "+
             "handle #{opts[:class_id]}:", [2])
        end

        # Deletes all filters, impossible to delete just one
        if vps_host_veth
          tc("filter del dev #{vps_host_veth} parent 1: protocol ip prio 16", [2])
        end

        host_netifs.each do |netif|
          tc("filter del dev #{netif} parent 1: protocol ip prio 16", [2])
        end

        if vps_host_veth
          tc("class del dev #{vps_host_veth} parent 1:1 classid 1:#{opts[:class_id]}", [2])
        end

        host_netifs.each do |netif|
          tc("class del dev #{netif} parent 1:1 classid 1:#{opts[:class_id]}", [2])
        end

        # Since all filters were deleted, set them up again
        get_vpses(Db.new).each do |vps|
          vps_host_veth = VethMap[vps.id][vps.netif]

          add_filters(host_netifs, 'src', vps.ips)
          add_filters([vps_host_veth], 'dst', vps.ips) if vps_host_veth
        end
      end
    end

    def update_ip(vps_id, opts)
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)
      vps_host_veth = VethMap[vps_id][opts[:netif]]

      sync do
        if opts[:max_tx] == 0 || opts[:max_rx] == 0
          # TODO: don't always deconfigure both sides of the shaper... but since
          # we have the shaper always enabled, it's not a big deal.
          remove_ip(vps_id, opts)

        else
          rets = []

          if vps_host_veth
            rets << tc("class change dev #{vps_host_veth} parent 1:1 "+
                      "classid 1:#{opts[:class_id]} htb rate "+
                      "#{opts[:max_rx]}bps ceil #{opts[:max_rx]}bps burst 300k", [2])
          end

          host_netifs.each do |netif|
            rets << tc("class change dev #{netif} parent 1:1 classid "+
                      "1:#{opts[:class_id]} htb rate "+
                      "#{opts[:max_tx]}bps ceil #{opts[:max_tx]}bps burst 300k", [2])

          end

          # If Either one of those commands reported
          #   'RTNETLINK answers: No such file or directory',
          # reinitialize the whole shaper
          if rets.detect { |ret| ret[:exitstatus] == 2 }
            add_ip(addr, opts)
          end
        end
      end
    end

    def update_root(tx, rx)
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)
      rets = []

      sync do
        VethMap.each_veth do |vps_id, vps_veth, host_veth|
          rets << tc("class change dev #{host_veth} parent 1: classid 1:1 htb "+
                      "rate #{rx}bps ceil #{rx}bps burst 1M", [2])
        end

        host_netifs.each do |netif|
          rets << tc("class change dev #{netif} parent 1: classid 1:1 htb "+
                     "rate #{tx}bps ceil #{tx}bps burst 1M", [2])
        end

        safe_init(Db.new) if rets.detect { |ret| ret[:exitstatus] == 2 }
      end
    end

    def flush
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)

      sync do
        host_netifs.each do |netif|
          tc("qdisc del dev #{netif} root handle 1:", [2])
        end

        VethMap.each_veth do |vps_id, vps_veth, host_veth|
          tc("qdisc del dev #{host_veth} root handle 1:", [2])
        end
      end
    end

    def reinit(db)
      sync do
        flush
        safe_init(db)
      end
    end

    def log_type
      'shaper'
    end

    protected
    IpInfo = Struct.new(:addr, :prefix, :version, :class_id, :max_tx, :max_rx)
    VpsInfo = Struct.new(:id, :netif, :ips)

    def safe_init(db)
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)
      tx = $CFG.get(:vpsadmin, :max_tx)
      rx = $CFG.get(:vpsadmin, :max_rx)

      # Setup main host interfaces
      host_netifs.each do |netif|
        tc("qdisc add dev #{netif} root handle 1: htb", [2])
        tc("class add dev #{netif} parent 1: classid 1:1 htb "+
           "rate #{tx}bps ceil #{tx}bps burst 1M", [2])
      end

      # Setup main host interfaces together with available per-VPS veth interfaces
      get_vpses(db).each do |vps|
        vps_host_veth = VethMap[vps.id][vps.netif]

        if vps_host_veth
          tc("qdisc add dev #{vps_host_veth} root handle 1: htb", [2])
          tc("class add dev #{vps_host_veth} parent 1: classid 1:1 htb "+
             "rate #{rx}bps ceil #{rx}bps burst 1M", [2])
        end

        shape_ips(vps, vps_host_veth, vps.ips)
      end
    end

    def shape_ips(vps, vps_host_veth, ips)
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)

      ips.each do |ip|
        if vps_host_veth
          tc("class add dev #{vps_host_veth} parent 1:1 classid 1:#{ip.class_id} "+
              "htb rate #{ip.max_rx}bps ceil #{ip.max_rx}bps burst 300k", [2])
        end

        host_netifs.each do |netif|
          tc("class add dev #{netif} parent 1:1 classid 1:#{ip.class_id} htb "+
              "rate #{ip.max_tx}bps ceil #{ip.max_tx}bps burst 300k", [2])
        end

        add_filters(host_netifs, 'src', [ip])
        add_filters([vps_host_veth], 'dst', [ip]) if vps_host_veth

        host_netifs.each do |netif|
          tc("qdisc add dev #{netif} parent 1:#{ip.class_id} handle #{ip.class_id}: "+
              "sfq perturb 10", [2])
        end

        if vps_host_veth
          tc("qdisc add dev #{vps_host_veth} parent 1:#{ip.class_id} "+
              "handle #{ip.class_id}: sfq perturb 10", [2])
        end
      end
    end

    def add_filters(netifs, dir, ips)
      netifs.each do |netif|
        ips.each do |ip|
          if ip.version == 4
            proto = 'ip'
            match = 'ip'
            prio = 16

          else
            proto = 'ipv6'
            match = 'ip6'
            prio = 17
          end

          tc("filter add dev #{netif} parent 1: protocol #{proto} prio #{prio} "+
             "u32 match #{match} #{dir} #{ip.addr}/#{ip.prefix} "+
             "flowid 1:#{ip.class_id}", [2])
        end
      end
    end

    def get_vps(db, vps_id)
      row = db.prepared('SELECT veth_name FROM vpses WHERE id = ?', vps_id).get
      fail "vps '#{vps_id}' not found" unless row

      vps = VpsInfo.new(vps_id, row['veth_name'], [])

      db.prepared(
        'SELECT
          ip_addr, ip.prefix, ip_version, class_id, max_tx, max_rx
        FROM ip_addresses ip
        INNER JOIN networks n ON n.id = ip.network_id
        WHERE
          ip.vps_id = ?
          AND
          n.role IN (0, 1)',
        vps_id
      ).each do |row|
        vps.ips << IpInfo.new(
          row['ip_addr'],
          row['prefix'],
          row['ip_version'],
          row['class_id'],
          row['max_tx'],
          row['max_rx'],
        )
      end

      vps
    end

    def get_vpses(db)
      vpses = {}

      # Fetch VPSes and veth names
      db.prepared(
        'SELECT
          id, veth_name
        FROM vpses
        WHERE
          node_id = ?
          AND
          object_state < 3',
        $CFG.get(:vpsadmin, :node_id)
      ).each do |row|
        vpses[ row['id'] ] = VpsInfo.new(row['id'], row['veth_name'], [])
      end

      # Fetch IP addresses
      db.prepared(
        'SELECT
          vpses.id, ip_addr, ip.prefix, ip_version, class_id, max_tx, max_rx
        FROM vpses
        INNER JOIN ip_addresses ip ON ip.vps_id = vpses.id
        INNER JOIN networks n ON n.id = ip.network_id
        WHERE
          vpses.node_id = ?
          AND
          ip.vps_id = vpses.id
          AND
          object_state < 3
          AND
          n.role IN (0, 1)',
        $CFG.get(:vpsadmin, :node_id)
      ).each do |row|
        vps = vpses[ row['id'] ]

        unless vps
          log(
            :warn,
            "VPS #{row['id']} for IP #{row['ip_addr']}/#{row['prefix']} not found"
          )
          next
        end

        vps.ips << IpInfo.new(
          row['ip_addr'],
          row['prefix'],
          row['ip_version'],
          row['class_id'],
          row['max_tx'],
          row['max_rx'],
        )
      end

      vpses.sort { |a, b| a[0] <=> b[0] }.map { |k, v| v }
    end

    def tc(arg, valid_rcs=[])
      syscmd("#{$CFG.get(:bin, :tc)} #{arg}", valid_rcs: valid_rcs)
    end

    def sync
      if @mutex.owned?
        yield
      else
        @mutex.synchronize { yield }
      end
    end
  end
end
