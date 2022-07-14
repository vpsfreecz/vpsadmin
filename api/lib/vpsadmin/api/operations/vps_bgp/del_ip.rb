require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::VpsBgp::DelIp < Operations::Base
    # @param [::VpsBgpPeer] vps_bgp_peer
    # @param [::VpsBgpIpAddress] vps_bgp_ip
    # @return [TransactionChain]
    def run(vps_bgp_peer, vps_bgp_ip)
      if vps_bgp_ip.vps_bgp_peer != vps_bgp_peer
        raise Exceptions::OperationError, 'invalid IP address'
      end

      chain, _ = TransactionChains::VpsBgp::DelIp.fire(vps_bgp_peer, vps_bgp_ip)
      chain
    end
  end
end
