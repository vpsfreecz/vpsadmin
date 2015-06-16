module Transactions::Firewall
  class UnregIp < ::Transaction
    t_name :firewall_unreg_ip
    t_type 2015

    def params(ip, vps)
      self.t_vps = ip.vps_id
      self.t_server = vps.vps_server

      {
          addr: ip.addr,
          version: ip.version
      }
    end
  end
end
