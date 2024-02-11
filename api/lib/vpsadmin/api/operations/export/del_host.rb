require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::DelHost < Operations::Base
    # @param export [::Export]
    # @param host [::ExportHost]
    # @return [TransactionChain]
    def run(export, host)
      chain, = TransactionChains::Export::DelHosts.fire(export, [host])
      chain
    end
  end
end
