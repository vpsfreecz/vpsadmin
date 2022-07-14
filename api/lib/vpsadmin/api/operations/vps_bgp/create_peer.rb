require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::VpsBgp::CreatePeer < Operations::Base
    # @param [::Vps] vps
    # @param opts [Hash]
    # @option opts [::HostIpAddress] :host_ip_address
    # @option opts [String] :protocol
    # @option opts [Integer] :route_limit
    # @return [TransactionChain, ::VpsBgpPeer]
    def run(vps, opts)
      if vps.user_id != opts[:host_ip_address].ip_address.user_id
        raise Exceptions::OperationError, 'invalid vps / host_ip_address combination'
      end

      TransactionChains::VpsBgp::CreatePeer.fire(vps, opts)
    end
  end
end
