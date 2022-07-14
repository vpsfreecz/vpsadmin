module TransactionChains
  class VpsBgp::DestroyPeer < ::TransactionChain
    label 'BGP Peer-'

    # @param [::VpsBgpPeer] :vps_bgp_peer
    def link_chain(vps_bgp_peer, opts)
      lock(vps_bgp_peer.vps)
      lock(vps_bgp_peer)
      concerns(:affect, [vps_bgp_peer.vps.class.name, vps_bgp_peer.vps.id])

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :rollback])

      append_t(Transactions::VpsBgp::DestroyPeer, args: vps_bgp_peer) do |t|
        vps_bgp_peer.update!(confirmed: ::VpsBgpPeer.confirmed(:confirm_destroy))
        t.destroy(vps_bgp_peer)

        vps_bgp_peer.vps_bgp_ip_addresses.each do |bgp_ip|
          bgp_ip.update!(confirmed: ::VpsBgpIpAddress.confirmed(:confirm_destroy))
          t.destroy(bgp_ip)
        end

        remaining_peers = ::VpsBgpPeer
          .where(vps: vps_bgp_peer.vps)
          .where.not(confirmed: ::VpsBgpPeer.confirmed(:confirm_destroy))

        if remaining_peers.empty?
          t.edit(vps_bgp_peer.vps.vps_bgp_asn, vps_id: nil)
        end
      end

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :execute])
      append_t(Transactions::VpsBgp::PrunePeer, args: vps_bgp_peer)
    end
  end
end
