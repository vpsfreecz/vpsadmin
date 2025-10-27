module Transactions::NetworkInterface
  class DelRoute < ::Transaction
    t_name :vps_route_del
    t_type 2007
    queue :network

    # @param netif [::NetworkInterface]
    # @param ip [::IpAddress]
    # @param unregister [Boolean]
    # @param pool [::Pool, nil]
    def params(netif, ip, unregister = true, pool: nil)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      if netif.vps.container?
        {
          pool_fs: (pool || netif.vps.dataset_in_pool.pool).filesystem,
          veth_name: netif.name,
          addr: ip.addr,
          prefix: ip.prefix,
          version: ip.version,
          via: ip.route_via && ip.route_via.ip_addr,
          unregister:,
          id: ip.id,
          user_id: ip.user_id || netif.vps.user_id
        }
      else
        {
          vps_uuid: netif.vps.uuid.uuid,
          host_name: netif.host_name,
          guest_name: netif.guest_name,
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
end
