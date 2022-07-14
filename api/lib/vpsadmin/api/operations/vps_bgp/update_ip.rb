require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::VpsBgp::UpdateIp < Operations::Base
    # @param [::VpsBgpPeer] vps_bgp_peer
    # @param [Hash] opts
    # @option opts [String] :priority
    # @return [TransactionChain, ::VpsBgpIpAddress]
    def run(vps_bgp_ip, opts)
      TransactionChains::VpsBgp::UpdateIp.fire(vps_bgp_ip, opts)
    end
  end
end
