module Transactions::Firewall
  class UnregIp < ::Transaction
    t_name :firewall_unreg_ip
    t_type 2015
    queue :network
    keep_going

    def params(ip, vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        addr: ip.addr,
        prefix: ip.prefix,
        version: ip.version,
        id: ip.id,
        user_id: vps.user_id,
      }
    end
  end
end
