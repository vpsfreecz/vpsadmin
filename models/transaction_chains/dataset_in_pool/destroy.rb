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

    def link_chain(dataset_in_pool, recursive = false)
      lock(dataset_in_pool)

      if recursive
        @pool_id = dataset_in_pool.pool.id
        dataset_in_pool.dataset.subtree.arrange.each do |k, v|
          destroy_recursive(k, v)
        end

      else
        fail 'not implemented'
      end
    end

    # Destroy datasets in pool recursively. Datasets are destroyed
    # from the bottom ("youngest children") to the top ("oldest parents").
    def destroy_recursive(dataset, children)
      # First destroy children
      children.each do |k, v|
        if v.is_a?(::Dataset)
          dip = v.dataset_in_pools.where(pool_id: @pool_id).take

          if dip
            destroy_dataset(dip)
          end

        else
          destroy_recursive(k, v)
        end
      end

      # Destroy parent dataset
      dip = dataset.dataset_in_pools.where(pool_id: @pool_id).take

      if dip
        destroy_dataset(dip)
      end

    end

    def destroy_dataset(dataset_in_pool)
      append(Transactions::Storage::DestroyDataset, args: dataset_in_pool) do
        # Destroy snapshots, trees, branches, snapshot in pool in branches
        dataset_in_pool.dataset_trees.each do |tree|
          tree.branches.each do |branch|
            branch.snapshot_in_pool_in_branches.each do |sipib|
              destroy(sipib)
            end

            destroy(branch)
          end

          destroy(tree)
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
        destroy(dataset_in_pool)
        dataset_in_pool.update(confirmed: ::DatasetInPool.confirmed(:confirm_destroy))

        # Check if ::Dataset should be destroyed or marked for destroyal
        if dataset_in_pool.dataset.dataset_in_pools.where.not(confirmed: ::DatasetInPool.confirmed(:confirm_destroy)).count == 0
          destroy(dataset_in_pool.dataset)

        elsif dataset_in_pool.dataset.dataset_in_pools
                  .joins(:pool)
                  .where(confirmed: ::DatasetInPool.confirmed(:confirmed))
                  .where.not(pools: {role: Pool.roles[:backup]}).count == 0

          # Is now only in backup pools
          edit(dataset_in_pool.dataset, expiration: Time.now.utc + 30*24*60*60)
        end
      end
    end
  end
end
