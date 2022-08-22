module Transactions::Vps
  class RemoveVeth < ::Transaction
    t_name :netif_remove_veth_routed
    t_type 2019
    queue :vps

    def params(netif)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      {
        pool_fs: netif.vps.dataset_in_pool.pool.filesystem,
        name: netif.name,
        mac_address: netif.mac,
        max_tx: netif.max_tx,
        max_rx: netif.max_rx,
      }
    end
  end
end
