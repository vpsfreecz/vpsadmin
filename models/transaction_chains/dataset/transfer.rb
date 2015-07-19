module TransactionChains
  class Dataset::Transfer < ::TransactionChain
    label 'Transfer'

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

      port = ::PortReservation.reserve(
          dst_dataset_in_pool.pool.node,
          dst_dataset_in_pool.pool.node.addr,
          self.id ? self : dst_chain
      )

      # no snapshots on the destination
      if dst_last_snapshot.nil? || (dst_dataset_in_pool.pool.role == 'backup' && !snapshots_in_tree?(dst_dataset_in_pool))
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

          tree = get_or_create_tree(dst_dataset_in_pool)
          branch = get_or_create_branch(tree)
        end

        use_chain(Dataset::Send, args: [
                port,
                src_dataset_in_pool,
                dst_dataset_in_pool,
                transfer_snapshots,
                nil,
                branch,
                true
            ]
        )

      else
        # there are snapshots on the destination

        if dst_dataset_in_pool.pool.role == 'backup'
          tree = get_or_create_tree(dst_dataset_in_pool)
          branch = get_or_create_branch(tree)

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
              use_chain(Dataset::Send, args: [
                  port,
                  src_dataset_in_pool,
                  dst_dataset_in_pool,
                  transfer_snapshots,
                  nil,
                  branch
              ])

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

    def snapshots_in_tree?(dataset_in_pool)
      tree = dataset_in_pool.dataset_trees.where(head: true).take

      return false unless tree

      ::SnapshotInPoolInBranch.joins(branch: [:dataset_tree])
        .where(branches: {dataset_tree_id: tree.id}).count > 0
    end

    def get_or_create_tree(dataset_in_pool)
      tree = ::DatasetTree.find_by(dataset_in_pool: dataset_in_pool, head: true)

      unless tree
        last_index = dataset_in_pool.dataset_trees.all.maximum('index')

        tree = ::DatasetTree.create!(
            dataset_in_pool: dataset_in_pool,
            index: last_index ? last_index + 1 : 0,
            head: true,
            confirmed: ::DatasetTree.confirmed(:confirm_create)
        )

        append(Transactions::Storage::CreateTree, args: tree)
      end

      tree
    end

    def get_or_create_branch(tree)
      branch = ::Branch.find_by(dataset_tree: tree, head: true)

      unless branch
        branch = ::Branch.create!(
            dataset_tree: tree,
            name: Time.new.strftime('%Y-%m-%dT%H:%M:%S'),
            head: true,
            confirmed: ::Branch.confirmed(:confirm_create)
        )

        append(Transactions::Storage::BranchDataset, args: branch) do
          create(branch)
        end
      end

      branch
    end
  end
end
