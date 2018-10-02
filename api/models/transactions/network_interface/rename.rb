module Transactions::NetworkInterface
  class Rename < ::Transaction
    t_name :netif_rename
    t_type 2020
    queue :vps

    def params(netif, orig, new_name)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      {
        name: new_name,
        original: orig,
      }
    end
  end
end
