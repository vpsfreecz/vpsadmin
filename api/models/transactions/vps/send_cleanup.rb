module Transactions::Vps
  class SendCleanup < ::Transaction
    t_name :vps_send_cleanup
    t_type 3034
    storage_effect :osctl_send_cleanup
    queue :vps
    irreversible

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {}
    end
  end
end
