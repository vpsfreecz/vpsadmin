module TransactionChains
  # Migrate VPS to another node.
  class Vps::Migrate < ::TransactionChain
    label 'Migrate'
    urgent_rollback

    has_hook :pre_start,
        desc: 'Called before the VPS is started on the new node',
        context: 'TransactionChains::Vps::Migrate instance',
        args: {
          vps: 'destination Vps',
          running: 'true if the VPS was running before the migration'
        }
    has_hook :post_start,
        desc: 'Called after the VPS was started on the new node',
        context: 'TransactionChains::Vps::Migrate instance',
        args: {
          vps: 'destination Vps',
          running: 'true if the VPS was running before the migration'
        }

    # @param opts [Hash]
    # @option opts [Boolean] replace_ips (false)
    # @option opts [Hash] resources (nil)
    # @option opts [Boolean] handle_ips (true)
    # @option opts [Boolean] reallocate_ips (true)
    # @option opts [Boolean] outage_window (true)
    # @option opts [Boolean] send_mail (true)
    # @option opts [String] reason (nil)
    # @option opts [Boolean] cleanup_data (true) destroy datasets on the source node
    def link_chain(vps, dst_node, opts = {})
      @opts = set_hash_opts(opts, {
        replace_ips: false,
        resources: nil,
        handle_ips: true,
        reallocate_ips: true,
        outage_window: true,
        send_mail: true,
        reason: nil,
        cleanup_data: true,
      })

      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      dst_vps = ::Vps.find(vps.id)
      dst_vps.node = dst_node

      # Save VPS state
      running = vps.running?

      # Mail notification
      mail(:vps_migration_begun, {
        user: vps.user,
        vars: {
          vps: vps,
          src_node: vps.node,
          dst_node: dst_vps.node,
          outage_window: @opts[:outage_window],
          reason: opts[:reason],
        }
      }) if @opts[:send_mail] && vps.user.mailer_enabled

      # Create target dataset in pool.
      # No new dataset in pool is created in database, it is simply
      # moved to another pool.
      src_dip = vps.dataset_in_pool
      @src_pool = src_dip.pool
      @dst_pool = dst_node.pools.hypervisor.take!

      lock(src_dip)

      # Transfer resources if the destination node is in a different
      # environment.
      if vps.node.location.environment_id != dst_node.location.environment_id
        resources_changes = vps.transfer_resources_to_env!(
          vps.user,
          dst_node.location.environment,
          @opts[:resources]
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

        if vps.node.location.environment_id != dst_node.location.environment_id
          # This code expects that the datasets have a just one cluster resource,
          # which is diskspace.
          changes = src.transfer_resources_to_env!(vps.user, dst_node.location.environment)
          changes[changes.keys.first][:row_id] = dst.id
          resources_changes.update(changes)

        else
          ::ClusterResourceUse.for_obj(src).each do |use|
            resources_changes[use] = {row_id: dst.id}
          end
        end

        append(Transactions::Storage::CreateDataset, args: dst) do
          create(dst)
        end

        # Set all properties except for quotas to ensure send/recv will pass
        props = {}

        src.dataset_properties.where(inherited: false).each do |p|
          next if %w(quota refquota).include?(p.name)
          props[p.name.to_sym] = [p, p.value]
        end

        append(Transactions::Storage::SetDataset, args: [dst, props]) if props.any?
      end

      # Unmount VPS datasets & snapshots in other VPSes
      mounts = MountMigrator.new(self, vps, dst_vps)
      mounts.umount_others

      # Transfer datasets
      migration_snapshots = []

      unless @opts[:outage_window]
        # Reserve a slot in zfs_send queue
        append(Transactions::Queue::Reserve, args: [vps.node, :zfs_send])
      end

      datasets.each do |pair|
        src, dst = pair

        # Transfer private area. All subdatasets are transfered as well.
        # The two (or three) step transfer is done even if the VPS seems to be stopped.
        # It does not have to be the case, vpsAdmin can have outdated information.
        # First transfer is done when the VPS is running.
        migration_snapshots << use_chain(Dataset::Snapshot, args: src)
        use_chain(Dataset::Transfer, args: [src, dst])
      end

      if @opts[:outage_window]
        # Wait for the outage window to open
        append(Transactions::OutageWindow::Wait, args: [vps, 15])
        append(Transactions::Queue::Reserve, args: [vps.node, :zfs_send])
        append(Transactions::OutageWindow::InOrFail, args: [vps, 15])

        # Second transfer while inside the outage window. The VPS is still running.
        datasets.each do |pair|
          src, dst = pair

          migration_snapshots << use_chain(Dataset::Snapshot, args: src, urgent: true)
          use_chain(Dataset::Transfer, args: [src, dst], urgent: true)
        end

        # Check if we're still inside the outage window. We're in if the window
        # closes in not less than 5 minutes. Fail if not.
        append(Transactions::OutageWindow::InOrFail, args: [vps, 5], urgent: true)
      end

      # Stop the VPS
      use_chain(Vps::Stop, args: vps, urgent: true)

      datasets.each do |pair|
        src, dst = pair

        # The final transfer is done when the VPS is stopped
        migration_snapshots << use_chain(Dataset::Snapshot, args: src, urgent: true)
        use_chain(Dataset::Transfer, args: [src, dst], urgent: true)
      end

      # Set quotas when all data is transfered
      datasets.each do |pair|
        src, dst = pair
        props = {}

        src.dataset_properties.where(inherited: false, name: %w(quota refquota)).each do |p|
          props[p.name.to_sym] = [p, p.value]
        end

        append(Transactions::Storage::SetDataset, args: [dst, props]) if props.any?
      end

      dst_ip_addresses = vps.ip_addresses

      # Migration to different location - remove or replace
      # IP addresses
      if vps.node.location != dst_vps.node.location && @opts[:handle_ips]
        migrate_ip_addresses(vps, dst_vps)
      end

      # Regenerate mount scripts of the migrated VPS
      mounts.datasets = datasets
      mounts.remount_mine

      # Restore VPS state
      call_hooks_for(:pre_start, self, args: [dst_vps, running])
      use_chain(Vps::Start, args: dst_vps, urgent: true) if running
      call_hooks_for(:post_start, self, args: [dst_vps, running])

      # Remount and regenerate mount scripts of mounts in other VPSes
      mounts.remount_others

      # Release reserved spot in the queue
      append(Transactions::Queue::Release, args: [vps.node, :zfs_send], urgent: true)

      # Remove migration snapshots
      migration_snapshots.each do |sip|
        dst_sip = sip.snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
          dataset_in_pools: {pool_id: @dst_pool.id}
        ).take!

        use_chain(SnapshotInPool::Destroy, args: dst_sip, urgent: true)
      end

      # Move the dataset in pool to the new pool in the database
      chain = self

      append(Transactions::Utils::NoOp, args: dst_node.id, urgent: true) do
        edit(vps, dataset_in_pool_id: datasets.first[1].id)
        edit(vps, node_id: dst_node.id)

        # Transfer resources
        resources_changes.each do |use, changes|
          edit(use, changes) unless changes.empty?
        end

        # Handle dataset properties
        datasets.each do |src, dst|
          src.dataset_properties.all.each do |p|
            edit(p, dataset_in_pool_id: dst.id)
          end

          chain.migrate_dataset_plans(src, dst, self)
        end

        just_create(vps.log(:node, {
          src: {id: vps.node_id, name: vps.node.domain_name},
          dst: {id: dst_vps.node_id, name: dst_vps.node.domain_name},
        }))
      end

      # Call DatasetInPool.migrated hook
      datasets.each do |src, dst|
        src.call_hooks_for(:migrated, self, args: [src, dst])
      end

      # Setup firewall and shapers
      # Unregister from firewall and remove shaper on source node
      if @opts[:handle_ips]
        use_chain(Vps::FirewallUnregister, args: vps, urgent: true)
        use_chain(Vps::ShaperUnset, args: vps, urgent: true)
      end

      # Is is needed to register IP in fw and shaper when changing location,
      # as IPs are removed or replaced sooner.
      if vps.node.location == dst_vps.node.location
        # Register to firewall and set shaper on destination node
        use_chain(Vps::FirewallRegister, args: [dst_vps, dst_ip_addresses], urgent: true)
        use_chain(Vps::ShaperSet, args: [dst_vps, dst_ip_addresses], urgent: true)
      end

      # Destroy old dataset in pools
      # Do not detach backup trees and branches
      # Do not delete repeatable tasks - they are re-used for new datasets
      use_chain(DatasetInPool::Destroy, args: [src_dip, {
        recursive: true,
        top: true,
        tasks: false,
        detach_backups: false,
        destroy: @opts[:cleanup_data],
      }])

      # Destroy old root
      append(Transactions::Vps::Destroy, args: vps)

      # Mail notification
      mail(:vps_migration_finished, {
        user: vps.user,
        vars: {
          vps: vps,
          src_node: vps.node,
          dst_node: dst_vps.node,
          outage_window: @opts[:outage_window],
          reason: opts[:reason],
        }
      }) if @opts[:send_mail] && vps.user.mailer_enabled

      # fail 'ohnoes'
      self
    end

    def recursive_serialize(dataset, children)
      ret = []

      # First parents
      dip = dataset.dataset_in_pools.where(pool: @src_pool).take

      return ret unless dip

      lock(dip)

      dst = ::DatasetInPool.create!(
        pool: @dst_pool,
        dataset_id: dip.dataset_id,
        label: dip.label,
        min_snapshots: dip.min_snapshots,
        max_snapshots: dip.max_snapshots,
        snapshot_max_age: dip.snapshot_max_age
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
            dataset_id: dip.dataset_id,
            label: dip.label,
            min_snapshots: dip.min_snapshots,
            max_snapshots: dip.max_snapshots,
            snapshot_max_age: dip.snapshot_max_age
          )

          lock(dst)

          ret << [dip, dst]

        else
          ret.concat(recursive_serialize(k, v))
        end
      end

      ret
    end

    def migrate_dataset_plans(src_dip, dst_dip, confirmable)
      plans = []

      src_dip.dataset_in_pool_plans.includes(
        environment_dataset_plan: [:dataset_plan]
      ).each do |dip_plan|
        plans << dip_plan
      end

      return if plans.empty?

      plans.each do |dip_plan|
        plan = dip_plan.environment_dataset_plan.dataset_plan
        name = plan.name.to_sym

        # Remove src dip from the plan
        VpsAdmin::API::DatasetPlans.plans[name].unregister(
          src_dip,
          confirmation: confirmable
        )

        # Do not add the plan in the target environment if it is for admins only
        begin
          next unless ::EnvironmentDatasetPlan.find_by!(
            dataset_plan: plan,
            environment: dst_dip.pool.node.location.environment,
          ).user_add

        rescue ActiveRecord::RecordNotFound
          next  # the plan is not present in the target environment
        end

        begin
          VpsAdmin::API::DatasetPlans.plans[name].register(
            dst_dip,
            confirmation: confirmable
          )

        rescue VpsAdmin::API::Exceptions::DatasetPlanNotInEnvironment
          # This exception should never be raised, as the not-existing plan
          # in the target environment is caught by the rescue above.
          next
        end
      end
    end

    # Replaces IP addresses if migrating to another location. Handles reallocation
    # of cluster resources when migrating to a different environment.
    #
    # 1) Within one location
    #    - nothing to do
    # 2) Different location, same env
    #    - no reallocation needed, just find replacement ips
    # 3) Different location, different env
    #    - find replacements, reallocate to different env
    def migrate_network_interfaces(vps, dst_vps)
      if vps.network_interfaces.count > 1
        fail 'migration of VPS with multiple network interfaces is not implemented'
      end

      vps.network_interfaces.each do |netif|
        migrate_ip_addresses(netif, dst_vps)
      end
    end

    def migrate_ip_addresses(netif, dst_vps)
      dst_netif = ::NetworkInterface.find(netif.id)
      dst_netif.vps = dst_vps

      # Add the same number of IP addresses from the target location
      if @opts[:replace_ips]
        dst_ip_addresses = []

        netif.ip_addresses.joins(:network).order(
          'networks.ip_version, ip_addresses.order'
        ).each do |ip|
          begin
            replacement = ::IpAddress.pick_addr!(
              dst_vps.user,
              dst_vps.node.location,
              ip.network.ip_version,
              ip.network.role.to_sym,
            )

          rescue ActiveRecord::RecordNotFound
            dst_ip_addresses << [ip, nil]
            next
          end

          lock(replacement)

          dst_ip_addresses << [ip, replacement]
        end

        if dst_ip_addresses.detect { |v| v[1].nil? }
          src = dst_ip_addresses.map { |v| v[0] }
          dst = dst_ip_addresses.map { |v| v[1] }.compact
          errors = []

          %i(ipv4 ipv4_private ipv6).each do |r|
            diff = filter_ip_addresses(src, r).count - filter_ip_addresses(dst, r).count
            next if diff == 0

            errors << "#{diff} #{r} addresses"
          end

          fail "Not enough free IP addresses in the target location: #{errors.join(', ')}"
        end

        # Migrating to a different environment, transfer IP cluster resources
        if @opts[:reallocate_ips] \
           && vps.node.location.environment_id != dst_vps.node.location.environment_id
          changes = transfer_ip_addresses(
            vps.user,
            dst_ip_addresses,
            vps.node.location.environment,
            dst_vps.node.location.environment,
          )

          unless changes.empty?
            append_t(Transactions::Utils::NoOp, args: find_node_id, urgent: true) do |t|
              changes.each { |obj, change| t.edit(obj, change) }
            end
          end
        end

        dst_ip_addresses.each do |src_ip, dst_ip|
          append(
            Transactions::NetworkInterface::DelRoute,
            args: [netif, src_ip, false],
            urgent: true
          ) do
            edit(src_ip, vps_id: nil)
            edit(src_ip, user_id: nil) if src_ip.user_id
          end

          append(
            Transactions::NetworkInterface::AddRoute,
            args: [dst_netif, dst_ip],
            urgent: true
          ) do
            edit(dst_ip, vps_id: dst_vps.id, order: src_ip.order)

            if !dst_ip.user_id && dst_vps.node.location.environment.user_ip_ownership
              edit(dst_ip, user_id: dst_vps.user_id)
            end
          end
        end

      else
        # Remove all IP addresses
        dst_ip_addresses = []
        ips = []

        netif.ip_addresses.each { |ip| ips << ip }
        use_chain(
          NetworkInterface::DelRoute,
          args: [
            dst_vps, ips,
            resource_obj: vps, unregister: false, reallocate: @opts[:reallocate_ips]
          ],
          urgent: true
        )
      end
    end

    # Transfer number of `ips` belonging to `user` from `src_env` to `dst_env`.
    #
    # TODO: this method will not properly work when the VPS has multiple
    # network interfaces. The resource reallocation needs to take into account
    # previous runs of this method -- one for each interface.
    def transfer_ip_addresses(user, ips, src_env, dst_env)
      ret = {}

      src_user_env = user.environment_user_configs.find_by!(
        environment: src_env,
      )
      dst_user_env = user.environment_user_configs.find_by!(
        environment: dst_env,
      )

      new_ips = ips.select { |_, ip| !ip.user_id }.map { |v| v[1] }

      %i(ipv4 ipv4_private ipv6).each do |r|
        # Free only standalone IP addresses
        standalone_ips = ips.map { |v| v[0] }

        src_use = src_user_env.reallocate_resource!(
          r,
          src_user_env.send(r) - filter_ip_addresses(standalone_ips, r).count,
          user: user,
          confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        )

        # Allocate all _new_ IP addresses
        dst_use = dst_user_env.reallocate_resource!(
          r,
          dst_user_env.send(r) + filter_ip_addresses(new_ips, r).count,
          user: user,
          confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        )

        ret[src_use] = {value: src_use.value}
        ret[dst_use] = {value: dst_use.value}
      end

      ret
    end

    def filter_ip_addresses(ips, r)
      case r
      when :ipv4
        ips.select do |ip|
          ip.network.ip_version == 4 && ip.network.role == 'public_access'
        end

      when :ipv4_private
        ips.select do |ip|
          ip.network.ip_version == 4 && ip.network.role == 'private_access'
        end

      when :ipv6
        ips.select { |ip| ip.network.ip_version == 6 }
      end
    end

    # Handle my mounts of datasets and snapshots of other VPSes
    #   local -> local - no change needed
    #   local -> remote - change mount, create clone for snapshot if needed
    #   remote -> remote - regenerate mounts to handle different IPs, move
    #                      snapshot clone to new destination
    #   remote -> local - change mount, remove clone of snapshot if needed
    # Handle mounts of my datasets and snapshots in other VPSes
    #   is the same
    class MountMigrator
      def initialize(chain, src_vps, dst_vps)
        @chain = chain
        @src_vps = src_vps
        @dst_vps = dst_vps
        @my_mounts = []
        @others_mounts = {}

        sort_mounts
      end

      def datasets=(datasets)
        # Map of source datasets to destination datasets
        @ds_map = {}

        datasets.each do |pair|
          # @ds_map[ src ] = dst
          @ds_map[pair[0]] = pair[1]
        end
      end

      def umount_others
        @others_mounts.each do |v, vps_mounts|
          @chain.append(
            Transactions::Vps::Umount,
            args: [v, vps_mounts.select { |m| m.enabled? }]
          )
        end
      end

      def remount_mine
        obj_changes = {}

        @my_mounts.each do |m|
          obj_changes.update(
            migrate_mine_mount(m)
          )
        end

        @chain.use_chain(Vps::Mounts, args: @dst_vps, urgent: true)

        unless obj_changes.empty?
          @chain.append(Transactions::Utils::NoOp, args: @dst_vps.node_id,
                        urgent: true) do
            obj_changes.each do |obj, changes|
              edit_before(obj, changes)
            end
          end
        end
      end

      def remount_others
        @others_mounts.each do |vps, mounts|
          obj_changes = {}

          mounts.each do |m|
            obj_changes.update(
              migrate_others_mount(m)
            )
          end

          @chain.use_chain(Vps::Mounts, args: vps, urgent: true)

          @chain.append(
            Transactions::Vps::Mount,
            args: [vps, mounts.select { |m| m.enabled? }.reverse],
            urgent: true
          ) do
            obj_changes.each do |obj, changes|
              edit_before(obj, changes)
            end
          end
        end
      end

      private
      def sort_mounts
        # Fetch ids of all descendant datasets in pool
        dataset_in_pools = @src_vps.dataset_in_pool.dataset.subtree.joins(
          :dataset_in_pools
        ).where(
          dataset_in_pools: {pool_id: @src_vps.dataset_in_pool.pool_id}
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
          :vps, :snapshot_in_pool, dataset_in_pool: [:dataset, pool: [:node]]
        ).where(
          'vps_id = ? OR (dataset_in_pool_id IN (?) OR snapshot_in_pool_id IN (?))',
          @src_vps.id, dataset_in_pools, snapshot_in_pools
        ).order('dst DESC').each do |mnt|
          if mnt.vps_id == @src_vps.id
            @my_mounts << mnt

          else
            @others_mounts[mnt.vps] ||= []
            @others_mounts[mnt.vps] << mnt
          end
        end
      end

      # Migrate a mount that is mounted in the migrated VPS (therefore mine)
      # and the mounted dataset or snapshot can be of the migrated VPS or from
      # elsewhere.
      def migrate_mine_mount(mnt)
        dst_dip = @ds_map[mnt.dataset_in_pool]

        is_subdataset = \
          mnt.dataset_in_pool.pool.node_id == @src_vps.node_id && \
          mnt.vps.dataset_in_pool.dataset.subtree_ids.include?(
            mnt.dataset_in_pool.dataset.id
          )

        is_local = @src_vps.node_id == mnt.dataset_in_pool.pool.node_id
        is_remote = !is_local

        if is_subdataset
          become_local = @dst_vps.node_id == dst_dip.pool.node_id
        else
          become_local = @dst_vps.node_id == mnt.dataset_in_pool.pool.node_id
        end

        become_remote = !become_local

        is_snapshot = !mnt.snapshot_in_pool.nil?
        new_snapshot = if is_snapshot && is_subdataset
                         ::SnapshotInPool.where(
                           snapshot_id: mnt.snapshot_in_pool.snapshot_id,
                           dataset_in_pool: dst_dip
                         ).take!
                       else
                         nil
                       end

        original = {
          dataset_in_pool_id: mnt.dataset_in_pool_id,
          snapshot_in_pool_id: mnt.snapshot_in_pool_id,
          mount_type: mnt.mount_type,
          mount_opts: mnt.mount_opts
        }

        changes = {}

        # Local -> remote:
        #   - change mount type
        #   - clone snapshot if needed
        if is_local && become_remote
          mnt.mount_type = 'nfs'
          mnt.mount_opts = '-n -t nfs -overs=3'

          if is_snapshot
            @chain.append(
                Transactions::Storage::CloneSnapshot,
                args: [mnt.snapshot_in_pool, mnt.vps.userns_map], urgent: true
            ) do
              increment(mnt.snapshot_in_pool, :reference_count)
            end
          end

        # Remote -> local:
        #   - change mount type
        #   - remote snapshot clone if needed
        elsif is_remote && become_local
          mnt.mount_type = 'bind'
          mnt.mount_opts = '--bind'

          if is_snapshot
            @chain.append(
              Transactions::Storage::RemoveClone,
              args: [mnt.snapshot_in_pool, mnt.vps.userns_map], urgent: true
            ) do
              decrement(mnt.snapshot_in_pool, :reference_count)
            end
          end

        # Remote -> remote:
        elsif is_remote && become_remote

        # Local -> local:
        #   - nothing to do
        elsif is_local && become_local

        end

        if is_subdataset
          mnt.dataset_in_pool = dst_dip

          if is_snapshot
            # Remove the mount link from snapshot_in_pool, because it would
            # delete mount, when the snapshot gets deleted in
            # DatasetInPool::Destroy.
            changes[mnt.snapshot_in_pool] = {
              mount_id: mnt.snapshot_in_pool.mount_id
            }
            mnt.snapshot_in_pool.update!(mount: nil)

            changes[new_snapshot] = {mount_id: nil}
            new_snapshot.update!(mount: mnt)

            mnt.snapshot_in_pool = new_snapshot
          end
        end

        mnt.save!

        changes[mnt] = original
        changes
      end

      # Migrate a mount that is mounted in another VPS (not the one being
      # migrated). The mounted dataset or snapshot belongs to the migrated VPS.
      def migrate_others_mount(mnt)
        dst_dip = @ds_map[mnt.dataset_in_pool]

        is_local = @src_vps.node_id == mnt.vps.node_id
        is_remote = !is_local

        become_local = @dst_vps.node_id == mnt.vps.node_id
        become_remote = !become_local

        is_snapshot = !mnt.snapshot_in_pool.nil?
        new_snapshot = if is_snapshot
                         ::SnapshotInPool.where(
                           snapshot_id: mnt.snapshot_in_pool.snapshot_id,
                           dataset_in_pool: dst_dip
                         ).take!
                       else
                         nil
                       end

        original = {
          dataset_in_pool_id: mnt.dataset_in_pool_id,
          snapshot_in_pool_id: mnt.snapshot_in_pool_id,
          mount_type: mnt.mount_type,
          mount_opts: mnt.mount_opts
        }

        changes = {}

        # Local -> remote:
        #   - change mount type
        #   - clone snapshot if needed
        if is_local && become_remote
          mnt.mount_type = 'nfs'
          mnt.mount_opts = '-n -t nfs -overs=3'

          if is_snapshot
            @chain.append(
              Transactions::Storage::CloneSnapshot,
              args: [new_snapshot, mnt.vps.userns_map], urgent: true
            ) do
              increment(new_snapshot, :reference_count)
            end
          end

        # Remote -> local:
        #   - change mount type
        #   - remote snapshot clone if needed
        elsif is_remote && become_local
          mnt.mount_type = 'bind'
          mnt.mount_opts = '--bind'

          if is_snapshot
            @chain.append(
              Transactions::Storage::RemoveClone,
              args: [mnt.snapshot_in_pool, mnt.vps.userns_map], urgent: true
            ) do
              decrement(mnt.snapshot_in_pool, :reference_count)
            end
          end

        # Remote -> remote:
        #   - update node IP address, remove snapshot on src and create on dst
        #     node
        elsif is_remote && become_remote
          if is_snapshot
            @chain.append(
              Transactions::Storage::RemoveClone,
              args: [mnt.snapshot_in_pool, mnt.vps.userns_map], urgent: true
            )
            @chain.append(
              Transactions::Storage::CloneSnapshot,
              args: [new_snapshot, mnt.vps.userns_map], urgent: true
            )
          end

        # Local -> local:
        #   - nothing to do
        elsif is_local && become_local

        end

        mnt.dataset_in_pool = dst_dip

        if is_snapshot
          # Remove the mount link from snapshot_in_pool, because it would
          # delete mount, when the snapshot gets deleted in
          # DatasetInPool::Destroy.
          changes[mnt.snapshot_in_pool] = {
            mount_id: mnt.snapshot_in_pool.mount_id
          }
          mnt.snapshot_in_pool.update!(mount: nil)

          changes[new_snapshot] = {mount_id: nil}
          new_snapshot.update!(mount: mnt)

          mnt.snapshot_in_pool = new_snapshot
        end

        mnt.save!

        changes[mnt] = original
        changes
      end
    end
  end
end
