require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::VpsBgp::UpdatePeer < Operations::Base
    # @param [::VpsBgpPeer] vps_bgp_peer
    # @param opts [Hash]
    # @option opts [::HostIpAddress] :host_ip_address
    # @option opts [String] :protocol
    # @option opts [Integer] :route_limit
    # @return [TransactionChain, ::VpsBgpPeer]
    def run(vps_bgp_peer, opts)
      if opts.has_key?(:host_ip_address) \
         && vps_bgp_peer.vps.user_id != opts[:host_ip_address].ip_address.user_id
        raise Exceptions::OperationError, 'invalid vps / host_ip_address combination'
      end

      # TODO: we should check that the new protocol matches existing BGP IP addresses

      TransactionChains::VpsBgp::UpdatePeer.fire(vps_bgp_peer, opts)
    end
  end
end
