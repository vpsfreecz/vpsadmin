module TransactionChains
  class Dataset::Rotate < ::TransactionChain
    label 'Rotate dataset snapshots'

    def link_chain(dataset_in_pool)
      lock(dataset_in_pool)

      @deleted = 0
      @min = dataset_in_pool.min_snapshots
      @max = dataset_in_pool.max_snapshots
      @oldest = Time.now - dataset_in_pool.snapshot_max_age # in seconds
      @count = dataset_in_pool.snapshot_in_pools.all.count

      return if @count <= @min

      if dataset_in_pool.pool.role == 'backup'

        SnapshotInPoolInBranch.includes(snapshot_in_pool: [:snapshot], branch: [{dataset_tree: :dataset_in_pool}])
          .where(dataset_trees: {dataset_in_pool_id: dataset_in_pool.id}).order('snapshots.id').each do |s|

          next if s.reference_count > 0

          if destroy?(s.snapshot_in_pool)
            @deleted += 1
            destroy_snapshot(s)
          end

          if stop?(s.snapshot_in_pool)
            break
          end

        end

      else # primary or hypervisor

        dataset_in_pool.snapshot_in_pools.includes(:snapshot).all.order('snapshots.id').each do |s|

          if destroy?(s)
            # Check if it is backed up.
            # Check if destroying it won't break the history.
            dataset_in_pool.dataset.dataset_in_pools
              .joins(:pool)
              .where(pools: {role: ::Pool.roles[:backup]}).each do |backup|

              # Is the snapshot in this dataset_in_pool? -> continue
              unless backup.snapshot_in_pools.find_by(snapshot_id: s.snapshot_id)
                # This snapshot is not backed up in dataset_in_pool +backup+.
                # It cannot be destroyed as it would break the history flow.
                return
              end

              # Is it the last snapshot of this dataset_in_pool? -> break
              last = backup.snapshot_in_pools.all.order('snapshot_id DESC').take

              if last && last.id == s.id
                # This snapshot is backed up in dataset_in_pool +backup+ but
                # it is the last snapshot there.
                # It cannot be destroyed as it would break the history flow.
                return
              end

            end

            @deleted += 1
            destroy_snapshot(s)
          end

          if stop?(s)
            break
          end

        end
      end
    end

    def destroy?(snapshot_in_pool)
      (snapshot_in_pool.snapshot.created_at < @oldest && (@count - @deleted) > @min) || ((@count - @deleted) > @max)
    end

    def stop?(snapshot_in_pool)
      (@count - @deleted) <= @min || (snapshot_in_pool.snapshot.created_at > @oldest && (@count - @deleted) <= @max)
    end

    def destroy_snapshot(s)
      if s.is_a?(SnapshotInPoolInBranch)
        s.update(confirmed: SnapshotInPoolInBranch.confirmed(:confirm_destroy))
        s.snapshot_in_pool.update(confirmed: SnapshotInPool.confirmed(:confirm_destroy))
        cleanup = cleanup_snapshot?(s.snapshot_in_pool)

        append(Transactions::Storage::DestroySnapshot, args: [s.snapshot_in_pool, s.branch]) do
          destroy(s)
          destroy(s.snapshot_in_pool)
          destroy(s.snapshot_in_pool.snapshot) if cleanup

          if s.snapshot_in_pool_in_branch
            decrement(s.snapshot_in_pool_in_branch, :reference_count)
          end
        end

        # Destroy the branch if it is empty.
        # Empty branch may still contain SnapshotInPoolInBranch rows, but they
        # are all marked for confirm_destroy.
        if s.branch.snapshot_in_pool_in_branches.where.not(confirmed: SnapshotInPoolInBranch.confirmed(:confirm_destroy)).count == 0
          append(Transactions::Storage::DestroyBranch, args: s.branch)
        end

        # Destroy the tree if it is empty, checking for child branches
        # with the same condition as above.
        if s.branch.dataset_tree.branches.where.not(confirmed: Branch.confirmed(:confirm_destroy)).count == 0
          append(Transactions::Storage::DestroyTree, args: s.branch.dataset_tree)
        end

      else # SnapshotInPool
        s.update(confirmed: SnapshotInPool.confirmed(:confirm_destroy))
        cleanup = cleanup_snapshot?(s)

        append(Transactions::Storage::DestroySnapshot, args: s) do
          destroy(s)
          destroy(s.snapshot) if cleanup
        end
      end
    end

    def cleanup_snapshot?(snapshot_in_pool)
      Snapshot.joins(:snapshot_in_pools)
        .where(snapshots: {id: snapshot_in_pool.snapshot_id})
        .where.not(snapshot_in_pools: {confirmed: SnapshotInPool.confirmed(:confirm_destroy)}).count == 0
    end
  end
end
