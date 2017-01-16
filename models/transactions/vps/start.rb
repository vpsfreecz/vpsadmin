module Transactions::Vps
  class Start < ::Transaction
    t_name :vps_start
    t_type 1001
    queue :vps

    def params(vps)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {onboot: true} # FIXME
    end
  end
end
