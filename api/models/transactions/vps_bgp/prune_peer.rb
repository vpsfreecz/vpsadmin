module Transactions::VpsBgp
  class PrunePeer < ::Transaction
    t_name :vps_bgp_prune_peer
    t_type 5505
    queue :network
    irreversible

    # @param [::VpsBgpPeer] vps_bgp_peer
    def params(vps_bgp_peer)
      self.node_id = vps_bgp_peer.vps.node_id
      self.vps_id = vps_bgp_peer.vps_id

      {
        pool_fs: vps_bgp_peer.vps.dataset_in_pool.pool.filesystem,
        peer_id: vps_bgp_peer.id,
      }
    end
  end
end
