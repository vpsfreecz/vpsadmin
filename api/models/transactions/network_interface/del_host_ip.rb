module Transactions::NetworkInterface
  class DelHostIp < ::Transaction
    t_name :netif_host_addr_del
    t_type 2023
    queue :network

    # @param netif [::NetworkInterface]
    # @param addr [::HostIpAddress]
    # @param pool [::Pool, nil]
    def params(netif, addr, pool: nil)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      if netif.vps.container?
        {
          pool_fs: (pool || netif.vps.dataset_in_pool.pool).filesystem,
          interface: netif.name,
          addr: addr.ip_addr,
          prefix: addr.ip_address.prefix,
          version: addr.version
        }
      else
        {
          vps_uuid: netif.vps.uuid.uuid,
          host_name: netif.host_name,
          guest_name: netif.guest_name,
          addr: addr.ip_addr,
          prefix: addr.ip_address.prefix,
          version: addr.version
        }
      end
    end
  end
end
