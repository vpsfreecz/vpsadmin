module Transactions::Shaper
  class Set < ::Transaction
    t_name :shaper_set
    t_type 2010
    queue :network

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
