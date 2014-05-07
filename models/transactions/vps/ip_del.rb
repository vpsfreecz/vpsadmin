module Transactions::Vps
  class IpDel < ::Transaction
    t_name :vps_ip_del
    t_type 2007

    def prepare(vps, ip)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          ipdel: ip.addr
      }
    end
  end
end
