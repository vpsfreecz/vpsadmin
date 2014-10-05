module TransactionChains
  # This chain supports only rollback on a hypervisor or primary pools.
  class DatasetRollback < ::TransactionChain
    def link_chain(dataset_in_pool, snapshot)
      # One of the four scenarios will occur:
      # 1) Snapshot is the last snapshot on the hypervisor
      #    -> just rollback
      # 2) Snapshot is on the hypervisor but not on any backup
      #    -> transfer, than rollback hypervisor, branch backup
      # 3) Snapshot is both on the hypervisor and the backup
      #    -> rollback on the hypervisor, branch backup
      # 4) Snapshot is not present on the hypervisor, it is in the backup
      #    -> backup all snapshots, transfer from backup to temporary
      #       dataset on the hypervisor,
      #       replace the dataset on hypervisor, branch backup

      lock(dataset_in_pool)

      # Fetch the last snapshot on the +dataset_in_pool+
      primary_last_snap = SnapshotInPool.where(dataset_in_pool: dataset_in_pool).order('snapshot_id DESC').take

      # Scenario 1)
      if primary_last_snap.snapshot_id == snapshot.id
        append(Transactions::Storage::Rollback, args: [dataset_in_pool, primary_last_snap])
        return
      end

      # Find the snapshot_in_pool on pool with hypervisor or primary role
      snapshot_on_primary = snapshot.snapshot_in_pools.joins(:dataset_in_pool, :pool)
        .where('pool.role IN (?, ?)', ::Pool.roles[:hypervisor], ::Pool.roles[:primary]).take

      # Scenario 2) or 3)
      if snapshot_on_primary
        # Transfer the snapshots to all backup dataset in pools if they aren't backed up yet
        dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where('pool.role = ?', ::Pool.roles[:backup]).each do |dst|
          use_chain(TransactionChains::DatasetTransfer, dataset_in_pool, dst)
        end

        append(Transactions::Storage::Rollback, args: [dataset_in_pool, snapshot_on_primary]) do
          # Delete newer snapshots then the one roll backing to from primary, as they are
          # destroyed by zfs rollback
          dataset_in_pool.snapshot_in_pools.where('id > ?', snapshot_on_primary.id).each do |s|
            destroy(s)
          end
        end

        branch_backup(dataset_in_pool, snapshot)

        return
      end

      # Scenario 4) - snapshot is available only in a backup

      # Backup all snapshots
      dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where('pool.role = ?', ::Pool.roles[:backup]).each do |dst|
        use_chain(TransactionChains::DatasetTransfer, dataset_in_pool, dst)
      end

      backup_snap = snapshot.snapshot_in_pools.joins(:dataset_in_pool, :pool)
        .where('pool.role = ?', ::Pool.roles[:backup]).take!

      append(Transactions::Storage::PrepareRollback, args: dataset_in_pool)
      append(Transactions::Storage::RemoteRollback, args: [dataset_in_pool, backup_snap])
      append(Transactions::Storage::ApplyRollback, args: [dataset_in_pool]) do
        # Delete all snapshots from primary except the one that is being restored
        dataset_in_pool.snapshot_in_pools.all.each do |s|
          destroy(s) unless s.snapshot_id == backup_snap.snapshot_id
        end
      end

      branch_backup(dataset_in_pool, snapshot)
    end

    def branch_backup(dataset_in_pool, snapshot)
      dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where('pool.role = ?', ::Pool.roles[:backup]).each do |ds|
        lock(ds)

        old = ds.branches.find_by!(head: true)
        snap_in_pool = snapshot.snapshot_in_pools.where(dataset_in_pool: ds).take!
        snap_in_branch = snap_in_pool.snapshot_in_pool_in_branches.find_by!(branch: old)

        head = ::Branch.create(
            dataset_in_pool: ds,
            name: snapshot.name,
            index: ds.branches.where(name: snapshot.name).maximum('index') + 1,
            head: true,
            confirmed: false
        )

        append(Transactions::Storage::BranchDataset, args: [head, snap_in_branch]) do
          # Remove old head
          edit(old, head: false)

          create(head)

          # Move older or equal SnapshotInPoolInBranches from old head to the new branch
          old.snapshot_in_pool_in_branches.where('snapshot_in_pool_id <= ?', snap_in_pool.id).each do |s|
            edit(s, branch_id: head.id)
          end

          i = 0

          old.snapshot_in_pool_in_branches.where('snapshot_in_pool_id > ?', snap_in_pool.id).each do |s|
            edit(s, snapshot_in_pool_in_branch_id: snap_in_branch.id)
            i += 1
          end

          # Update reference count - number of objects that are dependant on snap_in_branch
          edit(snap_in_branch, reference_count: snap_in_branch.reference_count + i)
        end
      end
    end
  end
end
