module Transactions::Vps
  class Stop < ::Transaction
    t_name :vps_stop
    t_type 1002

    def params(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server
      {}
    end
  end
end
