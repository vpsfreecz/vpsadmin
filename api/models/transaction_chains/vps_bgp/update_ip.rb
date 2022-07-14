module TransactionChains
  class VpsBgp::UpdateIp < ::TransactionChain
    label 'BGP Peer IP*'

    # @param [::VpsBgpIpAddress] vps_bgp_ip
    # @param [Hash] opts
    # @option opts [String] :priority
    # @return [::VpsBgpIpAddress]
    def link_chain(vps_bgp_ip, opts)
      vps_bgp_peer = vps_bgp_ip.vps_bgp_peer

      lock(vps_bgp_peer)
      concerns(:affect, [vps_bgp_peer.vps.class.name, vps_bgp_peer.vps.id])

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :rollback])

      found = false
      bgp_ips = vps_bgp_peer.vps_bgp_ip_addresses.where.not(
        confirmed: ::VpsBgpIpAddress.confirmed(:confirm_destroy),
      ).map do |bgp_ip|
        if bgp_ip == vps_bgp_ip
          bgp_ip.priority = opts[:priority]
          found = true
        end

        bgp_ip
      end

      fail 'failed to update the ip address' unless found

      append_t(
        Transactions::VpsBgp::UpdatePeer,
        args: [vps_bgp_peer],
        kwargs: {ip_addresses: bgp_ips},
      ) do |t|
        t.edit(vps_bgp_ip, priority: ::VpsBgpIpAddress.priorities[opts[:priority]])
      end

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :execute])
      append_t(Transactions::VpsBgp::PrunePeer, args: vps_bgp_peer)

      vps_bgp_ip
    end
  end
end
