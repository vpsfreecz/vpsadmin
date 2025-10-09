module TransactionChains
  class SnapshotInPool::Destroy < ::TransactionChain
    label 'Destroy snapshot in pool'

    # @param s [SnapshotInPoolInBranch, SnapshotInPool]
    # @param opts [Hash]
    # @option opts [Boolean] :destroy
    def link_chain(s, opts = {})
      lock(s)

      @opts = set_hash_opts(opts, { destroy: true })

      if s.is_a?(::SnapshotInPoolInBranch)
        lock(s.snapshot_in_pool)

        s.update!(confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_destroy))
        s.snapshot_in_pool.update!(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
        cleanup = cleanup_snapshot?(s.snapshot_in_pool)

        destroy_snapshot(s.snapshot_in_pool) if cleanup

        append_or_noop_t(Transactions::Storage::DestroySnapshot, args: [s.snapshot_in_pool, s.branch], noop: !@opts[:destroy]) do |t|
          t.destroy(s)
          t.destroy(s.snapshot_in_pool)
          t.destroy(s.snapshot_in_pool.snapshot) if cleanup

          t.decrement(s.snapshot_in_pool, :reference_count) if s.snapshot_in_pool_in_branch
        end

        # Destroy the branch if it is empty.
        # Empty branch may still contain SnapshotInPoolInBranch rows, but they
        # are all marked for confirm_destroy.
        if s.branch.snapshot_in_pool_in_branches.where.not(
          confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_destroy)
        ).count == 0

          s.branch.update!(confirmed: ::Branch.confirmed(:confirm_destroy))
          append_or_noop_t(Transactions::Storage::DestroyBranch, args: s.branch, noop: !@opts[:destroy]) do |t|
            t.destroy(s.branch)
          end

          # Destroy the tree if it is empty, checking for child branches
          # with the same condition as above.
          if s.branch.dataset_tree.branches.where.not(
            confirmed: ::Branch.confirmed(:confirm_destroy)
          ).count == 0

            s.branch.dataset_tree.update!(
              confirmed: ::DatasetTree.confirmed(:confirm_destroy)
            )
            append_or_noop_t(Transactions::Storage::DestroyTree, args: s.branch.dataset_tree, noop: !@opts[:destroy]) do |t|
              t.destroy(s.branch.dataset_tree)
            end
          end

        end

      else # SnapshotInPool
        s.update!(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
        cleanup = cleanup_snapshot?(s)

        destroy_snapshot(s) if cleanup

        append_or_noop_t(Transactions::Storage::DestroySnapshot, args: s, noop: !@opts[:destroy]) do |t|
          t.destroy(s)
          t.destroy(s.snapshot) if cleanup
        end
      end
    end

    protected

    def cleanup_snapshot?(snapshot_in_pool)
      ::Snapshot.joins(:snapshot_in_pools)
                .where(snapshots: { id: snapshot_in_pool.snapshot_id })
                .where.not(snapshot_in_pools: { confirmed: ::SnapshotInPool.confirmed(:confirm_destroy) }).count == 0
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
