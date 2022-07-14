require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::VpsBgp::RestartPeer < Operations::Base
    # @param [::VpsBgpPeer] vps_bgp_peer
    # @return [TransactionChain, ::VpsBgpPeer]
    def run(vps_bgp_peer)
      TransactionChains::VpsBgp::RestartPeer.fire(vps_bgp_peer)
    end
  end
end
