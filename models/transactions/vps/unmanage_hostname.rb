module Transactions::Vps
  class UnmanageHostname < ::Transaction
    t_name :vps_unmanage_hostname
    t_type 2016
    queue :vps

    def params(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          hostname: vps.hostname,
      }
    end
  end
end
