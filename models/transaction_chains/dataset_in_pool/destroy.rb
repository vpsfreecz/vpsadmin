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
      @datasets = []

      if recursive
        @pool_id = dataset_in_pool.pool.id
        dataset_in_pool.dataset.subtree.arrange.each do |k, v|
          destroy_recursive(k, v)
        end

      else
        fail 'not implemented'
      end

      # Acquire dataset locks
      @datasets.each { |dip| lock(dip) }

      # Datasets have to be umounted first
      affected_vpses = {}

      @datasets.each do |dip|
        affected_vpses.merge!(mounts_to_umount(dip)) do |_, oldval, newval|
          oldval << newval
        end
      end

      # Update mount action scripts
      affected_vpses.each_key do |vps|
        use_chain(TransactionChains::Vps::Mounts, args: vps)
      end

      # Umount
      affected_vpses.each do |vps, mounts|
        append(Transactions::Vps::Umount, args: [vps, mounts]) do
          mounts.each do |mnt|
            destroy(mnt)
          end
        end
      end

      # Destroy the first dataset
      destroy_dataset(@datasets.shift, top)

      # Destroy all remaining datasets
      @datasets.each do |dip|
        destroy_dataset(dip, true)
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
            @datasets << dip
          end

        else
          destroy_recursive(k, v)
        end
      end

      # Destroy parent dataset
      dip = dataset.dataset_in_pools.where(pool_id: @pool_id).take
      @datasets << dip if dip
    end

    def mounts_to_umount(dataset_in_pool)
      ret = {}

      dataset_in_pool.mounts.all.each do |mnt|
        lock(mnt.vps)
        lock(mnt)

        mnt.update!(confirmed: ::Mount.confirmed(:confirm_destroy))

        ret[mnt.vps] ||= []
        ret[mnt.vps] << mnt
      end

      dataset_in_pool.snapshot_in_pools.includes(mount: [:vps]).where.not(mount: nil).each do |snap|
        lock(snap.mount)

        ret[snap.mount.vps] ||= []
        ret[snap.mount.vps] << snap.mount
      end

      ret
    end

    def destroy_dataset(dataset_in_pool, destroy_top)
      if dataset_in_pool.pool.role == 'backup'
        dataset_in_pool.dataset_trees.each do |tree|
          use_chain(DatasetTree::Destroy, args: tree)
        end

      else
        dataset_in_pool.snapshot_in_pools.order('id, reference_count').each do |snap|
          use_chain(SnapshotInPool::Destroy, args: snap)
        end
      end

      append(Transactions::Storage::DestroyDataset, args: dataset_in_pool) do
        # Destroy snapshots, trees, branches, snapshot in pool in branches
        if %w(primary hypervisor).include?(dataset_in_pool.pool.role)
          # Detach dataset tree heads in all backups
          dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where(
              pools: {role: ::Pool.roles[:backup]}
          ).each do |backup|

            backup.dataset_trees.all.each do |tree|
              edit(tree, head: false)
            end
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

          dataset_in_pool.dataset_properties.update_all(
              confirmed: ::DatasetProperty.confirmed(:confirm_destroy)
          )
          dataset_in_pool.dataset_properties.each do |p|
            destroy(p)
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
