module Transactions::Vps
  class Hostname < ::Transaction
    t_name :vps_hostname
    t_type 2004
    queue :vps

    def params(vps, orig, hostname)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {
          hostname: hostname,
          original: orig
      }
    end
  end
end
