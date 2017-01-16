module Transactions::Firewall
  class RegIp < ::Transaction
    t_name :firewall_reg_ip
    t_type 2014
    queue :network

    def params(ip, vps)
      self.vps_id = ip.vps_id
      self.node_id = vps.vps_server

      {
          addr: ip.addr,
          version: ip.version,
          id: ip.id,
          user_id: vps.m_id,
      }
    end
  end
end
