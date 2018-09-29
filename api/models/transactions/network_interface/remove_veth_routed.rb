module Transactions::Vps
  class RemoveVeth < ::Transaction
    t_name :netif_remove_veth_routed
    t_type 2019
    queue :vps

    def params(vps)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      {
        name: netif.name,
        mac_address: netif.mac,
      }
    end
  end
end
