module Transactions::Vps
  class IpAdd < ::Transaction
    t_name :vps_ip_add
    t_type 2006

    def params(vps, ip)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          ipadd: ip.addr
      }
    end
  end
end
