module Transactions::Vps
  class Destroy < ::Transaction
    t_name :vps_destroy
    t_type 3002
    queue :vps
    irreversible

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {}
    end
  end
end
