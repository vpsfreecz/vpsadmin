module Transactions::NetworkInterface
  class DelHostIp < ::Transaction
    t_name :netif_host_addr_del
    t_type 2023
    queue :network

    # @param netif [::NetworkInterface]
    # @param addr [::HostIpAddress]
    def params(netif, addr)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      {
        interface: netif.name,
        addr: addr.ip_addr,
        prefix: addr.ip_address.prefix,
        version: addr.version,
      }
    end
  end
end
