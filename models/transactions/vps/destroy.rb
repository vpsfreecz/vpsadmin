module Transactions::Vps
  class Destroy < ::Transaction
    t_name :vps_destroy
    t_type 3002
    queue :vps
    irreversible

    def params(vps)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {}
    end
  end
end
