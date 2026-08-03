require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::Update < Operations::Base
    event_policy :transaction_chain,
                 reason: 'covered by transaction-chain operation lifecycle events',
                 atomic: false
    # @param export [::Export]
    # @param opts [Hash]
    # @option opts [::Snapshot] :snapshot
    # @option opts [Boolean] :all_vps
    # @option opts [Boolean] :rw
    # @option opts [Boolean] :sync
    # @option opts [Boolean] :subtree_check
    # @option opts [Boolean] :root_squash
    # @option opts [Integer] :threads
    # @option opts [Boolean] :enabled
    # @return [TransactionChain]
    def run(export, opts)
      TransactionChains::Export::Update.fire(export, opts)
    end
  end
end
