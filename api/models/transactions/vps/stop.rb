module Transactions::Vps
  class Stop < ::Transaction
    t_name :vps_stop
    t_type 1002
    queue :vps

    def params(vps, start_timeout: 'infinity', rollback_stop: true)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        start_timeout: start_timeout,
        autostart_priority: vps.autostart_priority,
        rollback_stop: rollback_stop,
      }
    end
  end
end
