require 'libosctl'

module NodeCtld
  # vpsAdmin-managed routes
  #
  # vpsAdmin adds source routes for primary IP addresses of all nodes, so that
  # communication between nodes uses IP addresses configured in vpsAdmin. This
  # is useful e.g. for NFS on nodes with multiple addresses from various subnets,
  # where it can simplify sharenfs configuration.
  # It is necessary to configure the routing system to ignore these routes and
  # not propagate them.
  class RoutingTable
    include OsCtl::Lib::Utils::Log
    include Utils::System

    def self.setup(db)
      rt = new
      rt.populate(db)
    end

    def populate(db)
      interfaces = $CFG.get(:vpsadmin, :net_interfaces)
      own_ip, other_ips = get_node_ips(db)

      other_ips.each do |ip|
        interfaces.each_with_index do |netif, i|
          syscmd(
            "ip route add #{ip}/32 dev #{netif} src #{own_ip} metric #{i+1}",
            valid_rcs: [2]
          )
        end
      end
    end

    def clear(db)
      interfaces = $CFG.get(:vpsadmin, :net_interfaces)
      own_ip, other_ips = get_node_ips(db)

      other_ips.each do |ip|
        interfaces.each do |netif|
          syscmd("ip route del #{ip}/32 dev #{netif} src #{own_ip}", valid_rcs: [2])
        end
      end
    end

    def log_type
      'routing-table'
    end

    protected
    def get_node_ips(db)
      node_id = $CFG.get(:vpsadmin, :node_id)
      own_ip = nil
      other_ips = []

      db.prepared('SELECT id, ip_addr FROM nodes').each do |row|
        if row['id'] == node_id
          own_ip = row['ip_addr']
        else
          other_ips << row['ip_addr']
        end
      end

      fail "unable to find own IP address" if own_ip.nil?

      [own_ip, other_ips]
    end
  end
end
