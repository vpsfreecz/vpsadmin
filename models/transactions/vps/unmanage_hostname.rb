module Transactions::Vps
  class UnmanageHostname < ::Transaction
    t_name :vps_unmanage_hostname
    t_type 2016
    queue :vps

    def params(vps)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {
          hostname: vps.hostname,
      }
    end
  end
end
