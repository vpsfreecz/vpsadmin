module TransactionChains
  # Migrate VPS to another node.
  class Vps::Migrate < ::TransactionChain
    label 'Migrate'
    urgent_rollback

    def link_chain(vps, dst_node)
      lock(vps)

      dst_vps = ::Vps.find(vps.id)
      dst_vps.node = dst_node

      # Save VPS state
      running = vps.running?

      # Create target dataset in pool.
      # No new dataset in pool is created in database, it is simply
      # moved to another pool.
      src_dip = vps.dataset_in_pool
      @src_pool = src_dip.pool
      @dst_pool = dst_node.pools.hypervisor.take!

      lock(src_dip)

      # Copy configs, create /vz/root/$veid
      append(Transactions::Vps::CopyConfigs, args: [vps, dst_node])
      append(Transactions::Vps::CreateRoot, args: [vps, dst_node])

      datasets = []

      vps.dataset_in_pool.dataset.subtree.arrange.each do |k, v|
        datasets.concat(recursive_serialize(k, v))
      end

      # Create datasets
      datasets.each do |pair|
        src, dst = pair

        append(Transactions::Storage::CreateDataset, args: dst) do
          create(dst)
        end
      end

      # Set zfs refquota properly
      # FIXME: should be set for all datasets
      append(Transactions::Vps::ApplyConfig, args: dst_vps)

      # Transfer datasets
      datasets.each do |pair|
        src, dst = pair

        # Transfer private area. All subdatasets are transfered as well.
        # The two step transfer is done even if the VPS seems to be stopped.
        # It does not have to be the case.
        # First transfer is done when the VPS is running.
        use_chain(Dataset::Snapshot, args: src)
        use_chain(Dataset::Transfer, args: [src, dst])
      end

      # Stop the VPS
      use_chain(Vps::Stop, args: vps)

      datasets.each do |pair|
        src, dst = pair

        # Seconds transfer is done when the VPS is stopped
        use_chain(Dataset::Snapshot, args: src, urgent: true)
        use_chain(Dataset::Transfer, args: [src, dst], urgent: true)
      end

      # Restore VPS state
      use_chain(Vps::Start, args: dst_vps, urgent: true) if running

      # Move the dataset in pool to the new pool in the database
      append(Transactions::Utils::NoOp, args: dst_node.id, urgent: true) do
        edit(vps, dataset_in_pool_id: datasets.first[1].id)
        edit(vps, vps_server: dst_node.id)

        # Handle dataset properties, actions and group snapshots
        datasets.each do |pair|
          src, dst = pair

          src.dataset_properties.all.each do |p|
            edit(p, dataset_in_pool_id: dst.id)
          end

          src.group_snapshots.all.each do |gs|
            edit(gs, dataset_in_pool_id: dst.id)
          end

          src.src_dataset_actions.all.each do |da|
            edit(da, src_dataset_in_pool_id: dst.id)
          end

          src.dst_dataset_actions.all.each do |da|
            edit(da, dst_dataset_in_pool_id: dst.id)
          end
        end
      end

      # Setup shapers
      # Remote shaper on source node
      use_chain(Vps::ShaperUnset, args: vps, urgent: true)

      # Set shaper on destination node
      use_chain(Vps::ShaperSet, args: dst_vps, urgent: true)

      # Destroy old dataset in pool
      # Do not delete repeatable tasks - they are re-used for new datasets
      use_chain(DatasetInPool::Destroy, args: [src_dip, true, true, false])

      # Destroy old root
      append(Transactions::Vps::Destroy, args: vps)

      # fail 'ohnoes'
    end

    def recursive_serialize(dataset, children)
      ret = []

      # First parents
      dip = dataset.dataset_in_pools.where(pool: @src_pool).take

      return ret unless dip

      lock(dip)

      dst = ::DatasetInPool.create!(
          pool: @dst_pool,
          dataset_id: dip.dataset_id
      )

      lock(dst)

      ret << [dip, dst]

      # Then children
      children.each do |k, v|
        if v.is_a?(::Dataset)
          dip = v.dataset_in_pools.where(pool: @src_pool).take
          next unless dip

          lock(dip)

          dst = ::DatasetInPool.create!(
              pool: @dst_pool,
              dataset_id: dip.dataset_id
          )

          lock(dst)

          ret << [dip, dst]

        else
          ret.concat(recursive_serialize(k, v))
        end
      end

      ret
    end
  end
end
