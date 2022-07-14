require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::VpsBgp::DestroyPeer < Operations::Base
    # @param [::VpsBgpPeer] vps_bgp_peer
    # @return [TransactionChain]
    def run(vps_bgp_peer)
      TransactionChains::VpsBgp::DestroyPeer.fire(vps_bgp_peer)
    end
  end
end
