module TransactionChains
  class Dataset::Transfer < ::TransactionChain
    label 'Transfer snapshots'

    def link_chain(src_dataset_in_pool, dst_dataset_in_pool)
      # FIXME: in theory, the transfer does not have to lock whole datasets.
      # It may be enough to lock only transfered snapshots. It would mean
      # that to deletedo something with a dataset, you'd have to get locks
      # for all its snapshots.
      lock(src_dataset_in_pool)
      lock(dst_dataset_in_pool)

      tree = nil
      branch = nil
      dst_last_snapshot = dst_dataset_in_pool.snapshot_in_pools.all.order('snapshot_id DESC').take

      # no snapshots on the destination
      if dst_last_snapshot.nil?
        # send everything
        # - first send the first snapshot from src to dst
        # - then send all snapshots incrementally, if there are any

        transfer_snapshots = src_dataset_in_pool.snapshot_in_pools.all.joins(:snapshot).order('id ASC')

        if transfer_snapshots.empty?
          # no snapshots to transfer
          return
        end

        # destination is branched
        if dst_dataset_in_pool.pool.role == 'backup'
          # create tree and branch unless it exists
          # create tree and branch unless it exists
          # mark tree and branch as head
          # put all snapshots inside it

          tree = DatasetTree.find_by(dataset_in_pool: dst_dataset_in_pool, head: true)

          unless tree
            tree = DatasetTree.create(
                dataset_in_pool: dst_dataset_in_pool,
                head: true,
                confirmed: DatasetTree.confirmed(:confirm_create)
            )

            append(Transactions::Storage::CreateTree, args: tree)
          end

          branch = Branch.find_by(dataset_tree: tree, head: true)

          unless branch
            branch = Branch.create(
                dataset_tree: tree,
                name: Time.new.strftime('%Y-%m-%dT%H:%M:%S'),
                head: true,
                confirmed: Branch.confirmed(:confirm_create)
            )

            append(Transactions::Storage::BranchDataset, args: branch) do
              create(branch)
            end
          end
        end

        append(Transactions::Storage::Transfer,
               args: [
                 src_dataset_in_pool,
                 dst_dataset_in_pool,
                 transfer_snapshots,
                 branch,
                 true
               ]) do
          transfer_snapshots.each do |snap|
            sip = SnapshotInPool.create(
                snapshot_id: snap.snapshot_id,
                dataset_in_pool: dst_dataset_in_pool,
                confirmed: SnapshotInPool.confirmed(:confirm_create)
            )

            create(sip)

            if dst_dataset_in_pool.pool.role == 'backup'
              create(SnapshotInPoolInBranch.create(
                   snapshot_in_pool: sip,
                   branch: branch,
                   confirmed: SnapshotInPoolInBranch.confirmed(:confirm_create)
              ))
            end
          end
        end

      else
        # there are snapshots on the destination

        if dst_dataset_in_pool.pool.role == 'backup'
          tree = DatasetTree.find_by!(dataset_in_pool: dst_dataset_in_pool, head: true)
          branch = Branch.find_by!(dataset_tree: tree, head: true)

          # select last snapshot from head branch
          dst_last_snapshot = branch.snapshot_in_pool_in_branches
            .joins(:snapshot_in_pool)
            .order('snapshot_id DESC').take!.snapshot_in_pool

          # dst_last_snapshot = SnapshotInPool
          #   .select('snapshot_in_pools.*')
          #   .joins(:snapshot_in_pool_in_branches, :branches)
          #   .where('branches.head = 1 AND snapshot_in_pool_in_branches.dataset_in_pool_id = ?', dst.id)
          #   .order('snapshot_id DESC').take
        end

        src_last_snapshot = nil
        transfer_snapshots = []

        # select all snapshots from source in reverse order
        src_dataset_in_pool.snapshot_in_pools.joins(:snapshot)
          .select('snapshot_in_pools.*, snapshots.*').order('snapshot_id DESC').each do |snap|
          src_last_snapshot ||= snap
          transfer_snapshots.insert(0, snap)

          if dst_last_snapshot.snapshot_id == snap.snapshot_id # found the common snapshot
            # incremental send from snap to src_last_snap
            # if they are the same, it is the last snapshot on source and nothing has to be sent
            unless src_last_snapshot.snapshot_id == snap.snapshot_id
              append(Transactions::Storage::Transfer,
                     args: [
                       src_dataset_in_pool,
                       dst_dataset_in_pool,
                       transfer_snapshots,
                       branch
              ]) do
                # Skip the first snapshot - it is already present on the destination
                transfer_snapshots[1..-1].each do |s|
                  sip = SnapshotInPool.create(
                      snapshot_id: s.snapshot_id,
                      dataset_in_pool: dst_dataset_in_pool,
                      confirmed: SnapshotInPool.confirmed(:confirm_create)
                  )

                  create(sip)

                  if dst_dataset_in_pool.pool.role == 'backup'
                    create(SnapshotInPoolInBranch.create(
                         snapshot_in_pool: sip,
                         branch: branch,
                         confirmed: SnapshotInPoolInBranch.confirmed(:confirm_create)
                    ))
                  end
                end
              end

              return
            end

            puts "nothing to transfer"
            return
          end
        end

        # FIXME report err, create new tree
        warn "history does not match, cannot make a transfer"

      end
    end
  end
end
