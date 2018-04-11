module Transactions::Vps
  class VethName < ::Transaction
    t_name :vps_veth_name
    t_type 2018
    queue :vps

    def params(vps, orig, new_name)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
          veth_name: new_name,
          original: orig,
      }
    end
  end
end
