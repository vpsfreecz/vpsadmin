module Transactions::NetworkInterface
  class CreateVethRouted < ::Transaction
    t_name :netif_create_veth_routed
    t_type 2018
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
