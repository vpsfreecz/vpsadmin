module TransactionChains
  class Snapshot::Destroy < ::TransactionChain
    label 'Destroy'

    def link_chain(snap)
      lock(snap)
      concerns(:affect, [snap.class.name, snap.id])

      if snap.dataset.dataset_in_pools.joins(:pool).where(
        pools: { role: ::Pool.roles[:backup] }
      ).count > 0
        raise 'cannot destroy snaphot with backups'
      end

      snap.snapshot_in_pools.includes(dataset_in_pool: [:pool]).each do |sip|
        raise 'reference_count > 0' if sip.reference_count > 0

        raise 'cannot destroy a snapshot from backup' if sip.dataset_in_pool.pool.role == 'backup'

        use_chain(SnapshotInPool::Destroy, args: sip)
      end
    end
  end
end
