module TransactionChains
  module Vps::Clone
    # Return chain that will handle clone of `vps` to `node`
    # @param vps [::Vps]
    # @param node [::Node]
    def self.chain_for(vps, node)
      src = vps.node.hypervisor_type
      dst = node.hypervisor_type

      if src == 'openvz' && dst == 'openvz'
        VzToVz

      elsif src == 'openvz' && dst == 'vpsadminos'
        VzToOs

      elsif src == 'vpsadminos' && dst == 'vpsadminos'
        OsToOs

      else
        raise VpsAdmin::API::Exceptions::OperationNotSupported,
              "Clone from #{src} to #{dst} is not supported"
      end
    end
  end
end
