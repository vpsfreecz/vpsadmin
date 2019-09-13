module TransactionChains
  class SnapshotInPool::FreeClone < ::TransactionChain
    # @param cl [SnapshotInPoolClone]
    def link_chain(cl)
      lock(cl)
      append_t(Transactions::Storage::DeactivateSnapshotClone, args: [cl]) do |t|
        t.edit(cl, state: ::SnapshotInPoolClone.states[:inactive])
      end
    end
  end
end
