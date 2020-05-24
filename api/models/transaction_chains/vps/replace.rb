module TransactionChains
  module Vps::Replace
    # Return chain that will handle replace of `vps` to `node`
    # @param vps [::Vps]
    # @param node [::Node]
    def self.chain_for(vps, node)
      src = vps.node.hypervisor_type
      dst = node.hypervisor_type

      if src == 'vpsadminos' && dst == 'vpsadminos'
        Os
      else
        raise VpsAdmin::API::Exceptions::OperationNotSupported,
              "Replace from #{src} to #{dst} is not supported"
      end
    end
  end
end
