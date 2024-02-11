module Transactions::Vps
  class Start < ::Transaction
    t_name :vps_start
    t_type 1001
    queue :vps

    def params(vps, start_timeout: 'infinity', rollback_start: true)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        start_timeout:,
        autostart_priority: vps.autostart_priority,
        rollback_start:
      }
    end
  end
end
