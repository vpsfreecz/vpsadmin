module Transactions::VpsBgp
  class RestartPeer < ::Transaction
    t_name :vps_bgp_restart_peer
    t_type 5506
    queue :network

    # @param [::VpsBgpPeer] vps_bgp_peer
    def params(vps_bgp_peer)
      self.node_id = vps_bgp_peer.vps.node_id
      self.vps_id = vps_bgp_peer.vps_id

      {
        peer_id: vps_bgp_peer.id
      }
    end
  end
end
