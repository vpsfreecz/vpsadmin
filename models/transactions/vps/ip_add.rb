module Transactions::Vps
  class IpAdd < ::Transaction
    t_name :vps_ip_add
    t_type 2006

    def params(vps, ip)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          addr: ip.addr,
          version: ip.version,
          shaper: {
              class_id: ip.class_id,
              max_tx: ip.max_tx,
              max_rx: ip.max_rx
          }
      }
    end
  end
end
