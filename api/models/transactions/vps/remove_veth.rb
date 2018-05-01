module Transactions::Vps
  class RemoveVeth < ::Transaction
    t_name :vps_remove_veth
    t_type 2019
    queue :vps

    def params(vps, interconnecting_ips)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
          veth_name: vps.veth_name,
          mac_address: vps.veth_mac,
          interconnecting_networks: {
              4 => interconnecting_ips[4].to_s,
              6 => interconnecting_ips[6].to_s,
          },
      }
    end
  end
end
