module Transactions::Vps
  class Destroy < ::Transaction
    t_name :vps_destroy
    t_type 3002

    def params(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {}
    end
  end
end
