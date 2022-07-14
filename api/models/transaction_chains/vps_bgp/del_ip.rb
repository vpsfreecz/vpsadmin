module TransactionChains
  class VpsBgp::DelIp < ::TransactionChain
    label 'BGP Peer IP-'

    # @param [::VpsBgpPeer] vps_bgp_peer
    # @param [::VpsBgpIpAddress] vps_bgp_ip
    def link_chain(vps_bgp_peer, vps_bgp_ip)
      lock(vps_bgp_peer)
      concerns(:affect, [vps_bgp_peer.vps.class.name, vps_bgp_peer.vps.id])

      vps_bgp_ip.update!(confirmed: ::VpsBgpIpAddress.confirmed(:confirm_destroy))

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :rollback])

      append_t(Transactions::VpsBgp::UpdatePeer, args: vps_bgp_peer) do |t|
        t.destroy(vps_bgp_ip)
      end

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :execute])
      append_t(Transactions::VpsBgp::PrunePeer, args: vps_bgp_peer)
    end
  end
end
