module Transactions::Vps
  class ShaperChange < ::Transaction
    t_name :vps_shaper_change
    t_type 2009

    def params(ip)
      self.t_vps = ip.vps_id
      self.t_server = ip.vps.vps_server

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
