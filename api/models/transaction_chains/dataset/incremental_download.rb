module TransactionChains
  class Dataset::IncrementalDownload < Dataset::BaseDownload
    label 'Download'

    def download(dl)
      backup_from_sip = dl.from_snapshot.snapshot_in_pools.joins(
        dataset_in_pool: [:pool]
      ).where(
        pools: { role: ::Pool.roles[:backup] }
      ).take

      # Prefer an existing backup base. If the target snapshot is not on the
      # same backup pool yet, transfer it there and download from backup.
      if backup_from_sip
        to_sip = dl.snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
          dataset_in_pools: { pool_id: backup_from_sip.dataset_in_pool.pool_id }
        ).take

        if to_sip
          lock(to_sip)
          lock(to_sip.dataset_in_pool)
          lock(backup_from_sip)

          dl.pool = to_sip.dataset_in_pool.pool
          return
        end

        to_sip = dl.snapshot.snapshot_in_pools.joins(
          dataset_in_pool: [:pool]
        ).where(
          pools: { role: [
            ::Pool.roles[:primary],
            ::Pool.roles[:hypervisor]
          ] }
        ).take!

        lock(backup_from_sip)
        lock(to_sip)

        use_chain(Dataset::Transfer, args: [
                    to_sip.dataset_in_pool,
                    backup_from_sip.dataset_in_pool
                  ])

        dl.pool = backup_from_sip.dataset_in_pool.pool
        return
      end

      pool_ids = dl.from_snapshot.snapshot_in_pools
                   .joins(:dataset_in_pool)
                   .pluck('dataset_in_pools.pool_id')

      to_sip = dl.snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
        dataset_in_pools: { pool_id: pool_ids }
      ).take!

      lock(to_sip)
      lock(to_sip.dataset_in_pool)

      from_sip = dl.from_snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
        dataset_in_pools: { pool_id: to_sip.dataset_in_pool.pool_id }
      ).take!

      lock(from_sip)

      dl.pool = to_sip.dataset_in_pool.pool
    end
  end
end
