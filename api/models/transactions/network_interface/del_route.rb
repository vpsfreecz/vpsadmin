module Transactions::NetworkInterface
  class DelRoute < ::Transaction
    t_name :vps_route_del
    t_type 2007
    queue :network

    # @param netif [::NetworkInterface]
    # @param ip [::IpAddress]
    # @param unregister [Boolean]
    def params(netif, ip, unregister = true)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      ret = {
        veth_name: netif.name,
        addr: ip.addr,
        prefix: ip.prefix,
        version: ip.version,
        unregister: unregister,
        id: ip.id,
        user_id: ip.user_id || netif.vps.user_id,
      }

      if unregister
        ret[:shaper] = {
          class_id: ip.class_id,
          max_tx: ip.max_tx,
          max_rx: ip.max_rx,
        }
      end

      ret
    end
  end
end
