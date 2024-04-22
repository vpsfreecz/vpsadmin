module Transactions::NetworkInterface
  class AddRoute < ::Transaction
    t_name :vps_route_add
    t_type 2006
    queue :network

    # @param netif [::NetworkInterface]
    # @param ip [::IpAddress]
    # @param register [Boolean]
    # @param via [::HostIpAddress]
    # @param pool [::Pool, nil]
    def params(netif, ip, register = true, via: nil, pool: nil)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      {
        pool_fs: (pool || netif.vps.dataset_in_pool.pool).filesystem,
        veth_name: netif.name,
        addr: ip.addr,
        prefix: ip.prefix,
        version: ip.version,
        via: via && via.ip_addr,
        register:,
        id: ip.id,
        user_id: ip.user_id || netif.vps.user_id
      }
    end
  end
end
