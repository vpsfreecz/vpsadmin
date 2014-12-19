module Transactions::Shaper
  class Unset < ::Transaction
    t_name :shaper_unset
    t_type 2011

    def params(ip, vps)
      self.t_vps = ip.vps_id
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
