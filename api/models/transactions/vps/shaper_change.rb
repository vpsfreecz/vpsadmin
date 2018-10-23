module Transactions::Vps
  class ShaperChange < ::Transaction
    t_name :vps_shaper_change
    t_type 2009
    queue :network

    def params(ip, tx, rx)
      self.vps_id = ip.network_interface.vps_id
      self.node_id = ip.network_interface.vps.node_id

      {
        veth_name: ip.network_interface.name,
        addr: ip.addr,
        prefix: ip.prefix,
        version: ip.version,
        shaper: {
          class_id: ip.class_id,
          max_tx: tx,
          max_rx: rx,
        },
        shaper_original: {
          class_id: ip.class_id,
          max_tx: ip.max_tx,
          max_rx: ip.max_rx,
        }
      }
    end
  end
end
