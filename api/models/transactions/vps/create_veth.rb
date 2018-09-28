module Transactions::Vps
  class CreateVeth < ::Transaction
    t_name :vps_create_veth
    t_type 2018
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
