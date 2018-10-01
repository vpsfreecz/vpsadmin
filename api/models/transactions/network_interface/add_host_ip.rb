module Transactions::NetworkInterface
  class AddHostIp < ::Transaction
    t_name :netif_host_addr_add
    t_type 2022
    queue :network

    # @param addr [::HostIpAddress]
    def params(addr)
      self.vps_id = addr.ip_address.network_interface.vps.id
      self.node_id = addr.ip_address.network_interface.vps.node_id

      {
        interface: addr.ip_address.network_interface.name,
        addr: addr.ip_addr,
        prefix: addr.ip_address.prefix,
        version: addr.version,
      }
    end
  end
end
