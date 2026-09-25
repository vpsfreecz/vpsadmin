module Transactions::Vps
  class SendRollbackConfig < ::Transaction
    t_name :vps_send_rollback_config
    t_type 3035
    storage_effect :osctl_send_rollback
    queue :vps

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {}
    end
  end
end
