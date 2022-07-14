module TransactionChains
  class VpsBgp::RestartPeer < ::TransactionChain
    label 'BGP Peer+-'

    # @param [::VpsBgpPeer] :vps_bgp_peer
    # @return [::VpsBgpPeer]
    def link_chain(vps_bgp_peer)
      lock(vps_bgp_peer.vps)
      lock(vps_bgp_peer)
      concerns(:affect, [vps_bgp_peer.vps.class.name, vps_bgp_peer.vps.id])

      append_t(Transactions::VpsBgp::RestartPeer, args: vps_bgp_peer)
      vps_bgp_peer
    end
  end
end
