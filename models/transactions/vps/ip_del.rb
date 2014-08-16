module Transactions::Vps
  class IpDel < ::Transaction
    t_name :vps_ip_del
    t_type 2007

    def params(vps, ip)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          addr: ip.addr,
          version: ip.version,
          shaper: {
              class_id: ip.class_id
          }
      }
    end
  end
end
