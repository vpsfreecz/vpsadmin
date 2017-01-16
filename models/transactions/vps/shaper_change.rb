module Transactions::Vps
  class ShaperChange < ::Transaction
    t_name :vps_shaper_change
    t_type 2009
    queue :network

    def params(ip, tx, rx)
      self.vps_id = ip.vps_id
      self.node_id = ip.vps.vps_server

      {
          addr: ip.addr,
          version: ip.version,
          shaper: {
              class_id: ip.class_id,
              max_tx: tx,
              max_rx: rx
          },
          shaper_original: {
              class_id: ip.class_id,
              max_tx: ip.max_tx,
              max_rx: ip.max_rx
          }
      }
    end
  end
end
