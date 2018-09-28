module Transactions::Vps
  class RemoveVeth < ::Transaction
    t_name :vps_remove_veth
    t_type 2019
    queue :vps

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        veth_name: vps.veth_name,
        mac_address: vps.veth_mac,
      }
    end
  end
end
