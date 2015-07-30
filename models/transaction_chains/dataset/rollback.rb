module TransactionChains
  # This chain supports only rollback on a hypervisor or primary pools.
  class Dataset::Rollback < ::TransactionChain
    label 'Rollback'

    def link_chain(dataset_in_pool, snapshot)
      # One of the four scenarios will occur:
      # 0) Snapshot does not have backups
      #    -> simply rollback, delete newer snapshots (check if it's possible)
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
      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

      # Scenario 0)
      if dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where(
             pools: {role: ::Pool.roles[:backup]}
         ).count == 0
        
        sip = snapshot.snapshot_in_pools.where(dataset_in_pool: dataset_in_pool).take
        fail 'nothing to rollback, integrity error' unless sip
        
        pre_local_rollback

        append(Transactions::Storage::Rollback, args: [
            dataset_in_pool,
            sip
        ]) do
          dataset_in_pool.snapshot_in_pools.where(
              'id > ?', sip.id
          ).order('id').each do |s|
            if s.reference_count > 0
              raise VpsAdmin::API::Exceptions::SnapshotInUse, s
            end

            s.update!(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
            s.snapshot.update!(confirmed: ::Snapshot.confirmed(:confirm_destroy))

            destroy(s)
            destroy(s.snapshot)
          end
        end

        post_local_rollback

        return
      end

      # Fetch the last snapshot on the +dataset_in_pool+
      primary_last_snap = ::SnapshotInPool.where(dataset_in_pool: dataset_in_pool).order('snapshot_id DESC').take

      # Find the snapshot_in_pool on pool with hypervisor or primary role
      snapshot_on_primary = snapshot.snapshot_in_pools.joins(dataset_in_pool: [:pool])
        .where('pools.role IN (?, ?)', ::Pool.roles[:hypervisor], ::Pool.roles[:primary]).take

      # Scenario 1)
      if primary_last_snap.snapshot_id == snapshot.id
        pre_local_rollback
        append(Transactions::Storage::Rollback, args: [dataset_in_pool, primary_last_snap])
        post_local_rollback
        return
      end

      # Scenario 2) or 3)
      if snapshot_on_primary
        # Transfer the snapshots to all backup dataset in pools if they aren't backed up yet
        dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where('pools.role = ?', ::Pool.roles[:backup]).each do |dst|
          use_chain(TransactionChains::Dataset::Transfer, args: [dataset_in_pool, dst])
        end

        pre_local_rollback

        append(Transactions::Storage::Rollback, args: [dataset_in_pool, snapshot_on_primary]) do
          # Delete newer snapshots then the one roll backing to from primary, as they are
          # destroyed by zfs rollback
          dataset_in_pool.snapshot_in_pools.where('id > ?', snapshot_on_primary.id).each do |s|
            destroy(s)
          end
        end

        post_local_rollback

        branch_backup(dataset_in_pool, snapshot)

        return
      end

      # Scenario 4) - snapshot is available only in a backup

      # Backup all snapshots
      dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where('pools.role = ?', ::Pool.roles[:backup]).each do |dst|
        use_chain(TransactionChains::Dataset::Transfer, args: [dataset_in_pool, dst])
      end

      backup_snap = snapshot.snapshot_in_pools.joins(dataset_in_pool: [:pool])
        .where('pools.role = ?', ::Pool.roles[:backup]).take!

      snap_in_branch = backup_snap.snapshot_in_pool_in_branches
                           .where.not(confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_destroy)).take!


      port = ::PortReservation.reserve(
          dataset_in_pool.pool.node,
          dataset_in_pool.pool.node.addr,
          self.id ? self : dst_chain
      )

      append(Transactions::Storage::PrepareRollback, args: dataset_in_pool)
      use_chain(Dataset::Send, args: [
          port,
          backup_snap.dataset_in_pool,
          dataset_in_pool,
          [backup_snap],
          snap_in_branch.branch,
          nil,
          true,
          :rollback
      ])

      pre_local_rollback

      append(Transactions::Storage::ApplyRollback, args: [dataset_in_pool]) do
        # Delete all snapshots from primary
        dataset_in_pool.snapshot_in_pools.all.each do |s|
          destroy(s) if s.snapshot_id != backup_snap.snapshot_id
        end
      end

      post_local_rollback

      branch_backup(dataset_in_pool, snapshot)
    end

    def branch_backup(dataset_in_pool, snapshot)
      dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where('pools.role = ?', ::Pool.roles[:backup]).each do |ds|
        lock(ds)

        snap_in_pool = snapshot.snapshot_in_pools.where(dataset_in_pool: ds).take!
        snap_in_branch = snap_in_pool.snapshot_in_pool_in_branches
          .where.not(confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_destroy)).take!
        snap_tree = snap_in_branch.branch.dataset_tree
        head_tree = ds.dataset_trees.find_by!(head: true)
        old_branch = snap_in_branch.branch

        last_snap = old_branch.snapshot_in_pool_in_branches
          .joins(snapshot_in_pool: [:snapshot])
          .order('snapshots.id DESC').take!

        # If the last snapshot in the branch is the same as the one rollbacking to,
        # it is pointless to create a new branch.
        # However, as it is, this method is never called when rollbacking to the last
        # snapshot, because the last snapshot has to be kept on primary/hypervisor
        # for history flow purposes, so it is just rollback there.
        # It might be an issue later, if we decide to use zfs bookmarks.
        if last_snap.id != snap_in_branch.id
          last_index = snap_tree.branches.where(name: snapshot.name).maximum('index')

          head = ::Branch.create!(
              dataset_tree: snap_tree,
              name: snapshot.name,
              index: last_index ? last_index + 1 : 0,
              head: true,
              confirmed: ::Branch.confirmed(:confirm_create)
          )

          append(Transactions::Storage::BranchDataset, args: [head, snap_in_branch]) do
            # Remove old head
            edit(old_branch, head: false)

            create(head)

            # Move older or equal SnapshotInPoolInBranches from old head to the new branch
            old_branch.snapshot_in_pool_in_branches.where('snapshot_in_pool_id <= ?', snap_in_pool.id).each do |s|
              edit(s, branch_id: head.id)
            end

            i = 0

            old_branch.snapshot_in_pool_in_branches.where('snapshot_in_pool_id > ?', snap_in_pool.id).each do |s|
              edit(s, snapshot_in_pool_in_branch_id: snap_in_branch.id)
              i += 1
            end

            # Update reference count - number of objects that are dependant on snap_in_branch
            edit(snap_in_pool, reference_count: snap_in_pool.reference_count + i)
          end
        end

        if snap_tree.id != head_tree.id
          append(Transactions::Utils::NoOp, args: ds.pool.node_id) do
            edit(head_tree, head: false)
            edit(snap_tree, head: true)
          end
        end
      end
    end

    # Called before the dataset is rollbacked on primary or hypervisor.
    def pre_local_rollback

    end

    # Called after the dataset is rollbacked on primary or hypervisor.
    def post_local_rollback

    end
  end
end
