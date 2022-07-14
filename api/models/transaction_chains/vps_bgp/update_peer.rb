module TransactionChains
  class VpsBgp::UpdatePeer < ::TransactionChain
    label 'BGP Peer*'

    # @param [::VpsBgpPeer] :vps_bgp_peer
    # @param opts [Hash]
    # @option opts [::HostIpAddress] :host_ip_address
    # @option opts [String] :protocol
    # @option opts [Integer] :route_limit
    # @return [::VpsBgpPeer]
    def link_chain(vps_bgp_peer, opts)
      lock(vps_bgp_peer.vps)
      lock(vps_bgp_peer)
      concerns(:affect, [vps_bgp_peer.vps.class.name, vps_bgp_peer.vps.id])

      vps_bgp_peer.assign_attributes(opts)
      raise ActiveRecord::RecordInvalid, vps_bgp_peer unless vps_bgp_peer.valid?

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :rollback])

      append_t(Transactions::VpsBgp::UpdatePeer, args: vps_bgp_peer) do |t|
        changes = {}

        vps_bgp_peer.changed.each do |attr|
          changes[attr] = vps_bgp_peer.send(attr)
        end

        t.edit(vps_bgp_peer, changes)
      end

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :execute])
      append_t(Transactions::VpsBgp::PrunePeer, args: vps_bgp_peer)

      vps_bgp_peer
    end
  end
end
