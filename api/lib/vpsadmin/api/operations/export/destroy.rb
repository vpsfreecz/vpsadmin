require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::Destroy < Operations::Base
    # @param export [::Export]
    # @return [TransactionChain]
    def run(export)
      chain, = TransactionChains::Export::Destroy.fire(export)
      chain
    end
  end
end
