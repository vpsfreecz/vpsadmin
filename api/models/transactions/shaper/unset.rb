module Transactions::Shaper
  class Unset < ::Transaction
    t_name :shaper_unset
    t_type 2011
    queue :network

    def params(ip, vps)
      self.vps_id = ip.vps_id
      self.node_id = vps.node_id

      {
        addr: ip.addr,
        version: ip.version,
        shaper: {
          class_id: ip.class_id,
          max_tx: ip.max_tx,
          max_rx: ip.max_rx,
        },
      }
    end
  end
end
