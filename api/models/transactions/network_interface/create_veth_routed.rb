module Transactions::NetworkInterface
  class CreateVethRouted < ::Transaction
    t_name :netif_create_veth_routed
    t_type 2018
    queue :vps

    def params(netif)
      self.vps_id = netif.vps.id
      self.node_id = netif.vps.node_id

      if netif.vps.container?
        {
          pool_fs: netif.vps.dataset_in_pool.pool.filesystem,
          name: netif.name,
          user_id: netif.vps.user_id,
          netif_id: netif.id,
          mac_address: netif.guest_mac_address.addr,
          max_tx: netif.max_tx,
          max_rx: netif.max_rx,
          enable: netif.enable
        }
      else
        {
          vps_uuid: netif.vps.uuid.uuid,
          host_name: netif.host_name,
          guest_name: netif.guest_name,
          user_id: netif.vps.user_id,
          netif_id: netif.id,
          host_mac: netif.host_mac_address.addr,
          guest_mac: netif.guest_mac_address.addr,
          max_tx: netif.max_tx,
          max_rx: netif.max_rx,
          enable: netif.enable
        }
      end
    end
  end
end
