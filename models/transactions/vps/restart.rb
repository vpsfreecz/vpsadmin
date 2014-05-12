module Transactions::Vps
  class Restart < ::Transaction
    t_name :vps_restart
    t_type 1003

    def params(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {onboot: true} # FIXME
    end
  end
end
