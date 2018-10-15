module Transactions::Shaper
  class Set < ::Transaction
    t_name :shaper_set
    t_type 2010
    queue :network

    def params(vps, ip)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        netif: ip.network_interface.name,
        addr: ip.addr,
        prefix: ip.prefix,
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
