module Transactions::Vps
  class Stop < ::Transaction
    t_name :vps_stop
    t_type 1002
    queue :vps

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id
      {}
    end
  end
end
