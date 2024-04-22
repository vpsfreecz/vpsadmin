module Transactions::NetworkInterface
  class AddHostIp < ::Transaction
    t_name :netif_host_addr_add
    t_type 2022
    queue :network

    # @param netif [::NetworkInterface]
    # @param addr [::HostIpAddress]
    # @param pool [::Pool, nil]
    def params(netif, addr, pool: nil)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      {
        pool_fs: (pool || netif.vps.dataset_in_pool.pool).filesystem,
        interface: netif.name,
        addr: addr.ip_addr,
        prefix: addr.ip_address.prefix,
        version: addr.version
      }
    end
  end
end
