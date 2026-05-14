module TransactionChains
  class Dataset::FullDownload < Dataset::BaseDownload
    label 'Download'

    def download(dl)
      primary = primary_snap_in_pool(dl.snapshot)
      backup = ::SnapshotInPoolInBranch.find_for_snapshot(
        dataset_in_pool: nil,
        snapshot: dl.snapshot
      )&.snapshot_in_pool
      sip = backup || primary
      raise 'snapshot is nowhere to be found!' unless sip

      lock(sip)
      lock(sip.dataset_in_pool)

      dl.pool = sip.dataset_in_pool.pool
    end

    protected

    def primary_snap_in_pool(snapshot)
      snapshot.snapshot_in_pools
              .includes(dataset_in_pool: [:pool])
              .joins(dataset_in_pool: [:pool])
              .where(
                pools: { role: [
                  ::Pool.roles[:hypervisor],
                  ::Pool.roles[:primary]
                ] }
              )
              .where.not(
                snapshot_in_pools: { confirmed: ::SnapshotInPool.confirmed(:confirm_destroy) }
              )
              .take
    end
  end
end
