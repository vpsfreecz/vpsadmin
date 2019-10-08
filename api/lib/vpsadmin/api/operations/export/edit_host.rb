require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::EditHost < Operations::Base
    # @param host [::ExportHost]
    # @param opts [Hash]
    # @option opts [Boolean] :rw
    # @option opts [Boolean] :sync
    # @option opts [Boolean] :subtree_check
    # @option opts [Boolean] :root_squash
    # @return [TransactionChain, ExportHost]
    def run(host, opts)
      TransactionChains::Export::EditHost.fire(host, opts)
    end
  end
end
