require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::VpsBgp::AddIp < Operations::Base
    # @param [::VpsBgpPeer] vps_bgp_peer
    # @param opts [Hash]
    # @option opts [::IpAddress] :ip_address
    # @option opts [String] :priority
    # @return [TransactionChain, ::VpsBgpIpAddress]
    def run(vps_bgp_peer, opts)
      if vps_bgp_peer.protocol == 'ipv4' && opts[:ip_address].version != 4
        raise Exceptions::OperationError, 'incompatible IP version: this peer is for IPv4'
      elsif vps_bgp_peer.protocol == 'ipv6' && opts[:ip_address].version != 6
        raise Exceptions::OperationError, 'incompatible IP version: this peer is for IPv6'
      end

      TransactionChains::VpsBgp::AddIp.fire(vps_bgp_peer, opts)
    end
  end
end
