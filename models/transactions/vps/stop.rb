module Transactions::Vps
  class Stop < ::Transaction
    t_name :vps_stop
    t_type 1002
    queue :vps

    def params(vps)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server
      {}
    end
  end
end
