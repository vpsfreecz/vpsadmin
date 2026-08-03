require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::Destroy < Operations::Base
    event_policy :transaction_chain,
                 reason: 'covered by transaction-chain operation lifecycle events',
                 atomic: false
    # @param export [::Export]
    # @return [TransactionChain]
    def run(export)
      chain, = TransactionChains::Export::Destroy.fire(export)
      chain
    end
  end
end
