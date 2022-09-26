module Transactions::Vps
  class SendSync < ::Transaction
    t_name :vps_send_sync
    t_type 3032
    queue :outage

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {}
    end
  end
end
