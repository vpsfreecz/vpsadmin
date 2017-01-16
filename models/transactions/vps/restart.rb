module Transactions::Vps
  class Restart < ::Transaction
    t_name :vps_restart
    t_type 1003
    queue :vps

    def params(vps)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {onboot: true} # FIXME
    end
  end
end
