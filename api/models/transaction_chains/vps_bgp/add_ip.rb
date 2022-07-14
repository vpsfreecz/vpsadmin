module TransactionChains
  class VpsBgp::AddIp < ::TransactionChain
    label 'BGP Peer IP+'

    # @param [::VpsBgpPeer] vps_bgp_peer
    # @param opts [Hash]
    # @option opts [::IpAddress] :ip_address
    # @option opts [String] :priority
    # @return [::VpsBgpIpAddress]
    def link_chain(vps_bgp_peer, opts)
      lock(vps_bgp_peer)
      concerns(:affect, [vps_bgp_peer.vps.class.name, vps_bgp_peer.vps.id])

      bgp_ip = ::VpsBgpIpAddress.create!(
        vps_bgp_peer: vps_bgp_peer,
        ip_address: opts[:ip_address],
        priority: opts[:priority]
      )

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :rollback])

      append_t(Transactions::VpsBgp::UpdatePeer, args: vps_bgp_peer) do |t|
        t.create(bgp_ip)
      end

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :execute])
      append_t(Transactions::VpsBgp::PrunePeer, args: vps_bgp_peer)

      bgp_ip
    end
  end
end
