module TransactionChains
  class Dataset::Rotate < ::TransactionChain
    label 'Rotate'

    def link_chain(dataset_in_pool)
      lock(dataset_in_pool)
      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

      @deleted = 0
      @min = dataset_in_pool.min_snapshots
      @max = dataset_in_pool.max_snapshots
      @oldest = Time.now.localtime - dataset_in_pool.snapshot_max_age # in seconds
      @count = dataset_in_pool.snapshot_in_pools.all.count

      return if @count <= @min

      if dataset_in_pool.pool.role == 'backup'

        ::SnapshotInPoolInBranch.includes(
          snapshot_in_pool: [:snapshot],
          branch: [{ dataset_tree: :dataset_in_pool }]
        ).where(
          dataset_trees: { dataset_in_pool_id: dataset_in_pool.id }
        ).order('snapshots.id').each do |s|
          next if s.snapshot_in_pool.reference_count > 0

          if destroy?(s.snapshot_in_pool)
            @deleted += 1
            use_chain(SnapshotInPool::Destroy, args: s)
          end

          break if stop?(s.snapshot_in_pool)
        end

      else # primary or hypervisor
        backups = dataset_in_pool.dataset.dataset_in_pools
                                 .joins(:pool)
                                 .where(pools: { role: ::Pool.roles[:backup], is_open: true })
                                 .to_a

        dataset_in_pool.snapshot_in_pools.includes(:snapshot).all.order('snapshots.id').each do |s|
          if s.reference_count > 0
            next

          elsif destroy?(s)
            break unless source_snapshot_destroyable_with_backups?(dataset_in_pool, backups, s.snapshot_id)

            @deleted += 1
            use_chain(SnapshotInPool::Destroy, args: s)
          end

          break if stop?(s)
        end
      end
    end

    def destroy?(snapshot_in_pool)
      (snapshot_in_pool.snapshot.created_at.localtime < @oldest && (@count - @deleted) > @min) || ((@count - @deleted) > @max)
    end

    def stop?(snapshot_in_pool)
      (@count - @deleted) <= @min || (snapshot_in_pool.snapshot.created_at.localtime > @oldest && (@count - @deleted) <= @max)
    end

    protected

    def source_snapshot_destroyable_with_backups?(source_dip, backups, snapshot_id)
      backups.each do |backup|
        return false unless backup_history_preserved_if_source_snapshot_removed?(source_dip, backup, snapshot_id)
      end

      true
    end

    def backup_history_preserved_if_source_snapshot_removed?(source_dip, backup_dip, snapshot_id)
      newer_source_ids = source_dip.snapshot_in_pools.where('snapshot_id > ?', snapshot_id).select(:snapshot_id)

      backup_dip.snapshot_in_pools.where(snapshot_id: newer_source_ids).exists?
    end
  end
end
