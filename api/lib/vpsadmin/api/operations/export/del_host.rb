require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::DelHost < Operations::Base
    event_policy :transaction_chain,
                 reason: 'covered by transaction-chain operation lifecycle events',
                 atomic: false
    # @param export [::Export]
    # @param host [::ExportHost]
    # @return [TransactionChain]
    def run(export, host)
      chain, = TransactionChains::Export::DelHosts.fire(export, [host])
      chain
    end
  end
end
