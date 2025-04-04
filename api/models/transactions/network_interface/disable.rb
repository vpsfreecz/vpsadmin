module Transactions::NetworkInterface
  class Disable < ::Transaction
    t_name :netif_disable
    t_type 2033
    queue :vps

    def params(netif)
      vps ||= netif.vps

      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        pool_fs: vps.dataset_in_pool.pool.filesystem,
        veth_name: netif.name
      }
    end
  end
end
