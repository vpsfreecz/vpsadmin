module Transactions::Vps
  class Restart < ::Transaction
    t_name :vps_restart
    t_type 1003
    queue :vps

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {autostart_priority: vps.autostart_priority}
    end
  end
end
