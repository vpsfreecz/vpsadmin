module TransactionChains
  class SnapshotInPool::Destroy < ::TransactionChain
    label 'Destroy snapshot in pool'

    def link_chain(s)
      lock(s)

      if s.is_a?(::SnapshotInPoolInBranch)
        lock(s.snapshot_in_pool)

        s.update(confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_destroy))
        s.snapshot_in_pool.update(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
        cleanup = cleanup_snapshot?(s.snapshot_in_pool)

        destroy_snapshot(s.snapshot_in_pool.snapshot) if cleanup

        append(Transactions::Storage::DestroySnapshot, args: [s.snapshot_in_pool, s.branch]) do
          destroy(s)
          destroy(s.snapshot_in_pool)
          destroy(s.snapshot_in_pool) if cleanup

          if s.snapshot_in_pool_in_branch
            decrement(s.snapshot_in_pool, :reference_count)
          end
        end

        # Destroy the branch if it is empty.
        # Empty branch may still contain SnapshotInPoolInBranch rows, but they
        # are all marked for confirm_destroy.
        if s.branch.snapshot_in_pool_in_branches.where.not(confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_destroy)).count == 0
          s.branch.update(confirmed: ::Branch.confirmed(:confirm_destroy))
          append(Transactions::Storage::DestroyBranch, args: s.branch)
        end

        # Destroy the tree if it is empty, checking for child branches
        # with the same condition as above.
        if s.branch.dataset_tree.branches.where.not(confirmed: Branch.confirmed(:confirm_destroy)).count == 0
          append(Transactions::Storage::DestroyTree, args: s.branch.dataset_tree)
        end

      else # SnapshotInPool
        s.update(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
        cleanup = cleanup_snapshot?(s)

        destroy_snapshot(s) if cleanup

        append(Transactions::Storage::DestroySnapshot, args: s) do
          destroy(s)
          destroy(s.snapshot) if cleanup
        end
      end
    end

    protected
    def cleanup_snapshot?(snapshot_in_pool)
      Snapshot.joins(:snapshot_in_pools)
          .where(snapshots: {id: snapshot_in_pool.snapshot_id})
          .where.not(snapshot_in_pools: {confirmed: ::SnapshotInPool.confirmed(:confirm_destroy)}).count == 0
    end

    def destroy_snapshot(sip)
      # Make download link orphans
      append(Transactions::Utils::NoOp, args: sip.dataset_in_pool.pool.node_id) do
        ::SnapshotDownload.where(snapshot: sip.snapshot).each do |dl|
          edit(dl, snapshot_id: nil)
        end
      end
    end
  end
end
