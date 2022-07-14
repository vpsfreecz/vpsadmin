module TransactionChains
  class VpsBgp::CreatePeer < ::TransactionChain
    label 'BGP Peer+'

    # @param [::Vps] :vps
    # @param opts [Hash]
    # @option opts [::HostIpAddress] :host_ip_address
    # @option opts [String] :protocol
    # @option opts [Integer] :route_limit
    # @return [::VpsBgpPeer]
    def link_chain(vps, opts)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      vps_bgp_peer = ::VpsBgpPeer.create!(
        vps: vps,
        host_ip_address: opts[:host_ip_address],
        protocol: opts[:protocol],
        enabled: true,
      )
      lock(vps_bgp_peer)

      asn, asn_allocation = allocate_asn(vps)

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :rollback])

      append_t(Transactions::VpsBgp::CreatePeer, args: vps_bgp_peer) do |t|
        t.edit_before(asn, vps_id: nil) if asn_allocation == :allocated
        t.create(vps_bgp_peer)
      end

      append_t(Transactions::VpsBgp::CommitPeer, args: [vps_bgp_peer, :execute])
      append_t(Transactions::VpsBgp::PrunePeer, args: vps_bgp_peer)

      vps_bgp_peer
    end

    protected
    def allocate_asn(vps)
      asn = ::VpsBgpAsn.find_by(vps: vps)
      return [asn, :existing] if asn

      asn = ::VpsBgpAsn.where(vps: nil).take
      fail 'no ASN available' if asn.nil?

      asn.update!(vps: vps)
      [asn, :allocated]
    end
  end
end
