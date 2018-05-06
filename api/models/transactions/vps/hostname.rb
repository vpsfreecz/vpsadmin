module Transactions::Vps
  class Hostname < ::Transaction
    t_name :vps_hostname
    t_type 2004
    queue :vps

    def params(vps, orig, hostname)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        hostname: hostname,
        original: orig,
      }
    end
  end
end
