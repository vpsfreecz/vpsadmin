module TransactionChains
  # Destroy dataset in pool.
  # If +recursive+ is true, all child datasets on the same pool
  # are destroyed as well. Related snapshots in pool are destroyed
  # as well.
  #
  # When dataset is in no primary/hypervisor pools
  # and is only in backup pool, it is marked to be deleted and its
  # expiration is set. If dataset is in no pools at all, it is
  # deleted immediately.
  class DatasetInPool::Destroy < ::TransactionChain
    label 'Destroy dataset in pool'

    def link_chain(dataset_in_pool, recursive = false, top = true, tasks = true)
      lock(dataset_in_pool)

      @tasks = tasks

      if recursive
        @pool_id = dataset_in_pool.pool.id
        dataset_in_pool.dataset.subtree.arrange.each do |k, v|
          destroy_recursive(k, v, top)
        end

      else
        fail 'not implemented'
      end
    end

    # Destroy datasets in pool recursively. Datasets are destroyed
    # from the bottom ("youngest children") to the top ("oldest parents").
    def destroy_recursive(dataset, children, top)
      # First destroy children
      children.each do |k, v|
        if v.is_a?(::Dataset)
          dip = v.dataset_in_pools.where(pool_id: @pool_id).take

          if dip
            destroy_dataset(dip, true)
          end

        else
          destroy_recursive(k, v, true)
        end
      end

      # Destroy parent dataset
      dip = dataset.dataset_in_pools.where(pool_id: @pool_id).take

      if dip
        destroy_dataset(dip, top)
      end

    end

    def destroy_dataset(dataset_in_pool, destroy_top)
      append(Transactions::Storage::DestroyDataset, args: dataset_in_pool) do
        # Destroy snapshots, trees, branches, snapshot in pool in branches
        case dataset_in_pool.pool.role
          when 'primary', 'hypervisor'
            # Detach dataset tree heads in all backups
            dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where(
                pools: {role: ::Pool.roles[:backup]}
            ).each do |backup|

              backup.dataset_trees.all.each do |tree|
                edit(tree, head: false)
              end

            end

          when 'backup'
            dataset_in_pool.dataset_trees.each do |tree|
              tree.branches.each do |branch|
                branch.snapshot_in_pool_in_branches.each do |sipib|
                  destroy(sipib)
                end

                destroy(branch)
              end

              destroy(tree)
            end

          else
            fail "unknown pool role '#{dataset_in_pool.pool.role}'"
        end

        dataset_in_pool.snapshot_in_pools.update_all(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))

        dataset_in_pool.snapshot_in_pools.each do |snap|
          destroy(snap)

          # Check if ::Snapshot should be destroyed as well
          if snap.snapshot.snapshot_in_pools.where.not(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy)).count == 0
            destroy(snap.snapshot)
          end
        end

        # Destroy dataset in pool
        if destroy_top
          if @tasks
            # Remove associated DatasetAction and RepeatableTask
            GroupSnapshot.where(dataset_in_pool: dataset_in_pool).each do |group|
              just_destroy(group)
            end

            DatasetAction.where(
                'src_dataset_in_pool_id = ? OR dst_dataset_in_pool_id = ?',
                dataset_in_pool.id, dataset_in_pool.id).each do |act|
              just_destroy(act)

              just_destroy(RepeatableTask.find_for!(act))
            end
          end

          destroy(dataset_in_pool)
          dataset_in_pool.update(confirmed: ::DatasetInPool.confirmed(:confirm_destroy))

          # Check if ::Dataset should be destroyed or marked for destroyal
          if dataset_in_pool.dataset.dataset_in_pools.where.not(confirmed: ::DatasetInPool.confirmed(:confirm_destroy)).count == 0
            destroy(dataset_in_pool.dataset)

          elsif dataset_in_pool.dataset.dataset_in_pools
                    .joins(:pool)
                    .where(confirmed: ::DatasetInPool.confirmed(:confirmed))
                    .where.not(pools: {role: ::Pool.roles[:backup]}).count == 0

            # Is now only in backup pools
            edit(dataset_in_pool.dataset, expiration: Time.now.utc + 30*24*60*60)
          end
        end
      end
    end
  end
end
