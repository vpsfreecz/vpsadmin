module TransactionChains
  # Migrate VPS to another node.
  class Vps::Migrate < ::TransactionChain
    label 'Migrate'
    urgent_rollback

    has_hook :pre_start
    has_hook :post_start

    def link_chain(vps, dst_node, replace_ips, resources = nil)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

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

      # Transfer resources if the destination node is in a different
      # environment.
      if vps.node.environment_id != dst_node.environment_id
        resources_changes = vps.transfer_resources_to_env!(
            vps.user,
            dst_node.environment,
            resources: resources
        )
      end

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

        # Transfer resources
        resources_changes ||= {}

        if vps.node.environment_id != dst_node.environment_id
          changes = src.transfer_resources_to_env!(vps.user, dst_node.environment)
          changes[changes.keys.first][:row_id] = dst.id

        else
          changes = {::ClusterResourceUse.for_obj(src) => {row_id: dst.id}}
        end


        resources_changes.update(changes)

        append(Transactions::Storage::CreateDataset, args: dst) do
          create(dst)
        end

        props = {}

        src.dataset_properties.where(inherited: false).each do |p|
          props[p.name.to_sym] = [p, p.value]
        end

        append(Transactions::Storage::SetDataset, args: [dst, props]) unless props.empty?
      end

      # Unmount VPS datasets & snapshots in other VPSes
      vps_mounts = umount_all_mounts(vps)

      # Transfer datasets
      migration_snapshots = []

      datasets.each do |pair|
        src, dst = pair

        # Transfer private area. All subdatasets are transfered as well.
        # The two step transfer is done even if the VPS seems to be stopped.
        # It does not have to be the case.
        # First transfer is done when the VPS is running.
        migration_snapshots << use_chain(Dataset::Snapshot, args: src)
        use_chain(Dataset::Transfer, args: [src, dst])
      end

      # Stop the VPS
      use_chain(Vps::Stop, args: vps)

      datasets.each do |pair|
        src, dst = pair

        # Seconds transfer is done when the VPS is stopped
        migration_snapshots << use_chain(Dataset::Snapshot, args: src, urgent: true)
        use_chain(Dataset::Transfer, args: [src, dst], urgent: true)
      end

      dst_ip_addresses = vps.ip_addresses

      # Migration to different location - remove or replace
      # IP addresses
      if vps.node.location != dst_vps.node.location
        # Add the same number of IP addresses from the target location
        if replace_ips
          dst_ip_addresses = []

          vps.ip_addresses.each do |ip|
            replacement = ::IpAddress.pick_addr!(dst_vps.user, dst_vps.node.location, ip.ip_v)

            append(Transactions::Vps::IpDel, args: [dst_vps, ip], urgent: true) do
              edit(ip, vps_id: nil)
            end

            append(Transactions::Vps::IpAdd, args: [dst_vps, replacement], urgent: true) do
              edit(replacement, vps_id: dst_vps.veid)

              if !replacement.user_id && dst_vps.node.environment.user_ip_ownership
                edit(replacement, user_id: dst_vps.user_id)
              end
            end

            dst_ip_addresses << replacement
          end

        else
          # Remove all IP addresses
          dst_ip_addresses = []
          ips = []

          vps.ip_addresses.each { |ip| ips << ip }
          use_chain(Vps::DelIp, args: [dst_vps, ips, vps], urgent: true)
        end
      end

      # Restore VPS state
      call_hooks_for(:pre_start, self, args: [dst_vps, running])
      use_chain(Vps::Start, args: dst_vps, urgent: true) if running
      call_hooks_for(:post_start, self, args: [dst_vps, running])

      # Remount and regenerate mount scripts
      remount_all_mounts(vps_mounts, datasets)

      # Remove migration snapshots
      migration_snapshots.each do |sip|
        dst_sip = sip.snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
            dataset_in_pools: {pool_id: @dst_pool.id}
        ).take!

        use_chain(SnapshotInPool::Destroy, args: dst_sip, urgent: true)
      end

      # Move the dataset in pool to the new pool in the database
      append(Transactions::Utils::NoOp, args: dst_node.id, urgent: true) do
        edit(vps, dataset_in_pool_id: datasets.first[1].id)
        edit(vps, vps_server: dst_node.id)

        # Transfer resources
        resources_changes.each do |use, changes|
          edit(use, changes) unless changes.empty?
        end

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

      # Setup firewall and shapers
      # Unregister from firewall and remove shaper on source node
      use_chain(Vps::FirewallUnregister, args: vps, urgent: true)
      use_chain(Vps::ShaperUnset, args: vps, urgent: true)

      # Register to firewall and set shaper on destination node
      use_chain(Vps::FirewallRegister, args: [dst_vps, dst_ip_addresses], urgent: true)
      use_chain(Vps::ShaperSet, args: [dst_vps, dst_ip_addresses], urgent: true)

      # Destroy old dataset in pools
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

    # Find all mounts of datasets and snapshots of +vps+ in all other
    # vpses.
    # Returns a hash of vps => mounts.
    def umount_all_mounts(vps)
      mounts = {}

      # Fetch ids of all descendant datasets in pool
      dataset_in_pools = vps.dataset_in_pool.dataset.subtree.joins(
          :dataset_in_pools
      ).where(
          dataset_in_pools: {pool_id: vps.dataset_in_pool.pool_id}
      ).pluck('dataset_in_pools.id')

      # Fetch all snapshot in pools of above datasets
      snapshot_in_pools = []

      ::SnapshotInPool.where(dataset_in_pool_id: dataset_in_pools).each do |sip|
        snapshot_in_pools << sip.id

        if sip.reference_count > 1
          # This shouldn't be possible, as every snapshot can be mounted
          # just once.
          fail "snapshot (s=#{sip.snapshot_id},sip=#{sip.id}) has too high a reference count"
        end
      end

      ::Mount.includes(
          :snapshot_in_pool, dataset_in_pool: [:dataset, :pool]
      ).where.not(vps: vps).where(
          '(dataset_in_pool_id IN (?) OR snapshot_in_pool_id IN (?))',
          dataset_in_pools, snapshot_in_pools
      ).order('dst DESC').each do |mnt|
        mounts[mnt.vps] ||= []
        mounts[mnt.vps] << mnt
      end

      mounts.each do |v, vps_mounts|
        append(Transactions::Vps::Umount, args: [v, vps_mounts])

        vps_mounts.each do |mnt|
          # The snapshot is mounted remotely via a clone.
          # The clone must be removed on the source node and recreated on destination.
          if mnt.snapshot_in_pool_id && mnt.snapshot_in_pool.dataset_in_pool.pool.node_id != v.vps_server
            append(Transactions::Storage::RemoveClone, args: mnt.snapshot_in_pool)
          end
        end
      end

      mounts
    end

    # Regenerate action scripts for all VPSes that have mounts of datasets
    # in +dst_vps+.
    # +vps_mounts+ is a hash of vps => mounts.
    def remount_all_mounts(vps_mounts, datasets)
      ds_map = {}

      datasets.each do |pair|
        # ds_map[ src ] = dst
        ds_map[pair[0]] = pair[1]
      end

      vps_mounts.each do |vps, mnts|
        db_changes = {}
        dereference = []

        mnts.each do |mnt|
          # Temporarily update dataset in pools of all mounts, so that they
          # are generated with correct information.
          orig_dip = mnt.dataset_in_pool

          if mnt.snapshot_in_pool_id && mnt.snapshot_in_pool.dataset_in_pool.pool.node_id != vps.vps_server
            remote = true

          elsif mnt.dataset_in_pool.pool.node_id != vps.vps_server
            remote = true

          else
            remote = false
          end

          db_changes[mnt] = {
              dataset_in_pool_id: mnt.dataset_in_pool_id,
              snapshot_in_pool_id: mnt.snapshot_in_pool_id,
              mount_type: mnt.mount_type,
              mount_opts: mnt.mount_opts
          }

          mnt.dataset_in_pool = ds_map[orig_dip]

          if mnt.snapshot_in_pool_id
            db_changes[mnt.snapshot_in_pool] = {
                mount_id: mnt.snapshot_in_pool.mount_id
            }
            mnt.snapshot_in_pool.update!(mount: nil)

            mnt.snapshot_in_pool = ds_map[orig_dip].snapshot_in_pools.where(snapshot_id: mnt.snapshot_in_pool.snapshot_id).take!
          end

          # The mount type may have changed from local to remote or the other way around
          if vps.vps_server == ds_map[orig_dip].pool.node_id
              mnt.mount_type = mnt.snapshot_in_pool_id ? 'zfs' : 'bind'
              mnt.mount_opts = mnt.snapshot_in_pool_id ? '-t zfs' : '--bind'
          else
              mnt.mount_type = 'nfs'
              mnt.mount_opts = '-overs=3'
          end

          mnt.save!

          # It is a remote mount and the snapshot clone must be recreated.
          if mnt.snapshot_in_pool_id && mnt.snapshot_in_pool.dataset_in_pool.pool.node_id != vps.vps_server
            append(Transactions::Storage::CloneSnapshot, args: mnt.snapshot_in_pool) do
              increment(mnt.snapshot_in_pool, :reference_count) unless remote
            end

          # The mount WAS remote but now is local. The cloned snapshot is already gone,
          # all that has to be done now is decrement reference count.
          elsif mnt.snapshot_in_pool_id && remote
            dereference << mnt.snapshot_in_pool
          end
        end

        use_chain(Vps::Mounts, args: vps, urgent: true)
        append(Transactions::Vps::Mount, args: [vps, mnts.reverse], urgent: true) do
          db_changes.each do |mnt, changes|
            edit_before(mnt, changes)
          end

          dereference.each do |sip|
            decrement(sip, :reference_count)
          end
        end
      end
    end
  end
end
