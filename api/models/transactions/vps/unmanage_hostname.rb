module Transactions::Vps
  class UnmanageHostname < ::Transaction
    t_name :vps_unmanage_hostname
    t_type 2016
    queue :vps

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        hostname: vps.hostname,
      }
    end
  end
end
