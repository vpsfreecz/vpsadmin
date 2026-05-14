module TransactionChains
  class Dataset::IncrementalDownload < Dataset::BaseDownload
    label 'Download'

    def download(dl)
      backup_pair = ::SnapshotInPoolInBranch.find_pair_for_incremental(
        snapshot: dl.snapshot,
        from_snapshot: dl.from_snapshot
      )

      if backup_pair
        backup_from_entry, backup_to_entry = backup_pair

        lock(backup_to_entry.snapshot_in_pool)
        lock(backup_to_entry.snapshot_in_pool.dataset_in_pool)
        lock(backup_from_entry.snapshot_in_pool)

        dl.pool = backup_to_entry.snapshot_in_pool.dataset_in_pool.pool
        return
      end

      backup_from_entry = ::SnapshotInPoolInBranch.find_head_for_snapshot(
        snapshot: dl.from_snapshot,
        open_pool: true
      )

      # Prefer backup only when the base is in the live head branch and the
      # target can be transferred from primary/hypervisor storage.
      if backup_from_entry
        to_sip = dl.snapshot.snapshot_in_pools.joins(
          dataset_in_pool: [:pool]
        ).where(
          pools: { role: [
            ::Pool.roles[:primary],
            ::Pool.roles[:hypervisor]
          ] }
        ).where.not(
          snapshot_in_pools: { confirmed: ::SnapshotInPool.confirmed(:confirm_destroy) }
        ).take

        if to_sip
          backup_from_sip = backup_from_entry.snapshot_in_pool

          lock(backup_from_sip)
          lock(to_sip)

          use_chain(Dataset::Transfer, args: [
                      to_sip.dataset_in_pool,
                      backup_from_sip.dataset_in_pool
                    ])

          dl.pool = backup_from_sip.dataset_in_pool.pool
          return
        end
      end

      pool_ids = dl.from_snapshot.snapshot_in_pools
                   .joins(dataset_in_pool: [:pool])
                   .where(
                     pools: { role: [
                       ::Pool.roles[:primary],
                       ::Pool.roles[:hypervisor]
                     ] }
                   )
                   .where.not(
                     snapshot_in_pools: { confirmed: ::SnapshotInPool.confirmed(:confirm_destroy) }
                   )
                   .pluck('dataset_in_pools.pool_id')

      to_sip = dl.snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
        dataset_in_pools: { pool_id: pool_ids }
      ).where.not(
        snapshot_in_pools: { confirmed: ::SnapshotInPool.confirmed(:confirm_destroy) }
      ).take

      raise 'no common snapshot history found for incremental download' unless to_sip

      lock(to_sip)
      lock(to_sip.dataset_in_pool)

      from_sip = dl.from_snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
        dataset_in_pools: { pool_id: to_sip.dataset_in_pool.pool_id }
      ).where.not(
        snapshot_in_pools: { confirmed: ::SnapshotInPool.confirmed(:confirm_destroy) }
      ).take!

      lock(from_sip)

      dl.pool = to_sip.dataset_in_pool.pool
    end
  end
end
