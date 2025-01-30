module Transactions::NetworkInterface
  class SetShaper < ::Transaction
    t_name :netif_set_shaper
    t_type 2031
    queue :vps

    def params(netif, name: nil, max_tx: nil, max_rx: nil, vps: nil)
      vps ||= netif.vps

      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        pool_fs: vps.dataset_in_pool.pool.filesystem,
        veth_name: name || netif.name,
        max_tx: max_tx && {
          new: max_tx,
          original: netif.max_tx
        },
        max_rx: max_rx && {
          new: max_rx,
          original: netif.max_rx
        }
      }
    end
  end
end
