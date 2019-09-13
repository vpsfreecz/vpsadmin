module TransactionChains
  class SnapshotInPool::PurgeClones < ::TransactionChain
    label 'Purge clones'
    allow_empty

    def link_chain
      ::SnapshotInPoolClone.where(
        state: ::SnapshotInPoolClone.states[:inactive],
      ).each do |cl|
        begin
          lock(cl)
        rescue ResourceLocked
          next
        end

        append_t(
          Transactions::Storage::RemoveClone,
          args: [cl],
          reversible: :keep_going,
        ) do |t|
          t.decrement(cl.snapshot_in_pool, :reference_count)
          t.destroy(cl)
        end
      end
    end
  end
end
