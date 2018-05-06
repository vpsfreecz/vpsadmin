module TransactionChains
  class Dataset::IncrementalDownload < Dataset::BaseDownload
    label 'Download'

    def download(dl)
      # 1) Locate snapshot1 and snapshot2, search for a common pool
      # 2) If snapshot1 is in the backup and snapshot2 on the primary, transfer
      #    snapshot2 to backup and then realize the download.

      # Pools on which the first snapshot is located
      pool_ids = dl.from_snapshot.snapshot_in_pools
        .joins(:dataset_in_pool)
        .pluck('dataset_in_pools.pool_id')

      to_sip = dl.snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
        dataset_in_pools: {pool_id: pool_ids}
      ).take

      if to_sip
        lock(to_sip)
        lock(to_sip.dataset_in_pool)

        from_sip = dl.from_snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
          dataset_in_pools: {pool_id: to_sip.dataset_in_pool.pool_id}
        ).take!

        lock(from_sip)

        dl.pool = to_sip.dataset_in_pool.pool

      else
        # Locate the first snapshot in a backup, the second on a primary pool
        from_sip = dl.from_snapshot.snapshot_in_pools.joins(
          dataset_in_pool: [:pool]
        ).where(
          pools: {role: ::Pool.roles[:backup]}
        ).take!

        to_sip = dl.snapshot.snapshot_in_pools.joins(
          dataset_in_pool: [:pool]
        ).where(
          pools: {role: [
            ::Pool.roles[:primary],
            ::Pool.roles[:hypervisor],
          ]}
        ).take!

        lock(from_sip)
        lock(to_sip)

        use_chain(Dataset::Transfer, args: [
          to_sip.dataset_in_pool,
          from_sip.dataset_in_pool,
        ])

        dl.pool = from_sip.dataset_in_pool.pool
      end
    end
  end
end
