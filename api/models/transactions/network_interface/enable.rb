module Transactions::NetworkInterface
  class Enable < ::Transaction
    t_name :netif_enable
    t_type 2032
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
