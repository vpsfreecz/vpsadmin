module TransactionChains
  class Dataset::Rotate < ::TransactionChain
    label 'Rotate'

    def link_chain(dataset_in_pool)
      lock(dataset_in_pool)
      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

      @deleted = 0
      @min = dataset_in_pool.min_snapshots
      @max = dataset_in_pool.max_snapshots
      @oldest = Time.now.utc - dataset_in_pool.snapshot_max_age # in seconds
      @count = dataset_in_pool.snapshot_in_pools.all.count

      return if @count <= @min

      if dataset_in_pool.pool.role == 'backup'

        ::SnapshotInPoolInBranch.includes(
          snapshot_in_pool: [:snapshot],
          branch: [{dataset_tree: :dataset_in_pool}]
        ).where(
          dataset_trees: {dataset_in_pool_id: dataset_in_pool.id}
        ).order('snapshots.id').each do |s|

          next if s.snapshot_in_pool.reference_count > 0

          if destroy?(s.snapshot_in_pool)
            @deleted += 1
            use_chain(SnapshotInPool::Destroy, args: s)
          end

          if stop?(s.snapshot_in_pool)
            break
          end

        end

      else # primary or hypervisor

        dataset_in_pool.snapshot_in_pools.includes(:snapshot).all.order('snapshots.id').each do |s|

          if s.reference_count > 0
            next

          elsif destroy?(s)
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

              if last && last.snapshot_id == s.snapshot_id
                # This snapshot is backed up in dataset_in_pool +backup+ but
                # it is the last snapshot there.
                # It cannot be destroyed as it would break the history flow.
                return
              end

            end

            @deleted += 1
            use_chain(SnapshotInPool::Destroy, args: s)
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
  end
end
