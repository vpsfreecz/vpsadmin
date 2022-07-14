module Transactions::VpsBgp
  class DestroyPeer < ::Transaction
    t_name :vps_bgp_destroy_peer
    t_type 5504
    queue :network

    # @param [::VpsBgpPeer] vps_bgp_peer
    def params(vps_bgp_peer)
      self.node_id = vps_bgp_peer.vps.node_id
      self.vps_id = vps_bgp_peer.vps_id

      {
        pool_fs: vps_bgp_peer.vps.dataset_in_pool.pool.filesystem,
        peer_id: vps_bgp_peer.id
      }
    end
  end
end
