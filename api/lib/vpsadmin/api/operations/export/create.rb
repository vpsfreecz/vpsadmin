require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::Create < Operations::Base
    event_policy :transaction_chain,
                 reason: 'covered by transaction-chain operation lifecycle events',
                 atomic: false
    # @param dataset [::Dataset]
    # @param opts [Hash]
    # @option opts [::Snapshot] :snapshot
    # @option opts [Boolean] :all_vps
    # @option opts [Boolean] :rw
    # @option opts [Boolean] :sync
    # @option opts [Boolean] :subtree_check
    # @option opts [Boolean] :root_squash
    # @option opts [Integer] :threads
    # @option opts [Boolean] :enabled
    # @return [TransactionChain, Export]
    def run(dataset, opts = {})
      TransactionChains::Export::Create.fire(dataset, opts)
    end
  end
end
