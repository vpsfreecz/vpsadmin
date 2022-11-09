module Transactions::Vps
  class Start < ::Transaction
    t_name :vps_start
    t_type 1001
    queue :vps

    def params(vps, start_timeout: 60*5)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        start_timeout: start_timeout,
        autostart_priority: vps.autostart_priority,
      }
    end
  end
end
