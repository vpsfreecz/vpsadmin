module Transactions::NetworkInterface
  class Rename < ::Transaction
    t_name :netif_rename
    t_type 2020
    queue :vps

    def params(netif, orig, new_name)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      if netif.vps.container?
        {
          pool_fs: netif.vps.dataset_in_pool.pool.filesystem,
          name: new_name,
          original: orig,
          netif_id: netif.id
        }
      else
        {
          vps_uuid: netif.vps.uuid.to_s,
          host_name: netif.host_name,
          guest_name: orig,
          new_guest_name: new_name,
          netif_id: netif.id
        }
      end
    end
  end
end
