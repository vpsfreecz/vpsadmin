module TransactionChains
  module Vps::Migrate
    # Return chain that will handle migration of `vps` to `node`
    # @param vps [::Vps]
    # @param node [::Node]
    def self.chain_for(vps, node)
      src = vps.node.hypervisor_type
      dst = node.hypervisor_type

      if src == 'openvz' && dst == 'openvz'
        VzToVz

      elsif src == 'openvz' && dst == 'vpsadminos'
        VzToOs

      elsif src == 'vpsadminos' && dst == 'openvz'
        OsToVz

      else
        fail "migration from #{src} to #{dst} is not supported"
      end
    end
  end
end
