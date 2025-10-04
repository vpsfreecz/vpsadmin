module TransactionChains
  # Migrate dataset from `primary` pool onto another pool
  class Dataset::Migrate < ::TransactionChain
    label 'Migrate'

    def link_chain(src_dataset_in_pool, dst_pool, restart_vps: false, maintenance_window_vps: nil, finish_weekday: nil, finish_minutes: nil, optional_maintenance_window: true, cleanup_data: true, send_mail: true, reason: nil)
      @src_pool = src_dataset_in_pool.pool
      @dst_pool = dst_pool

      @src_node = @src_pool.node
      @dst_node = @dst_pool.node

      @resources_changes = {}

      dataset_user = src_dataset_in_pool.dataset.user

      datasets = []

      src_dataset_in_pool.dataset.subtree.arrange.each do |k, v|
        datasets.concat(recursive_serialize(k, v))
      end

      # Check snapshot in pool clones -- there may not be any on the source pool
      src_primary_dip_ids = datasets.map { |src, _| src.id }

      clones = ::SnapshotInPoolClone.joins(:snapshot_in_pool).where(
        snapshot_in_pools: { dataset_in_pool_id: src_primary_dip_ids }
      )

      if clones.any?
        raise VpsAdmin::API::Exceptions::OperationNotSupported,
              'unable to migrate dataset with existing snapshot clones'
      end

      concerns(:affect, [src_dataset_in_pool.dataset.class.name, src_dataset_in_pool.dataset_id])

      # Gather exports
      exports = []

      datasets.each do |src, dst|
        export_count = src.exports.count

        if export_count > 1
          raise "More than one exports exists for #{src.dataset.full_name}"
        elsif export_count == 0
          next
        end

        src_export = src.exports.take!
        lock(src_export)

        dst_export = ::Export.find(src_export.id)
        dst_export.dataset_in_pool = dst

        exports << [src_export, dst_export]
      end

      # Affected VPS
      if restart_vps
        export_mounts = ::ExportMount.where(export: exports.map(&:first))
        vpses = export_mounts.map(&:vps).uniq
      end

      if !optional_maintenance_window || exports.any?
        maintenance_windows =
          if finish_weekday
            ::VpsMaintenanceWindow.make_for(
              nil,
              finish_weekday: finish_weekday,
              finish_minutes: finish_minutes
            )
          elsif maintenance_window_vps
            maintenance_window_vps.vps_maintenance_windows.where(is_open: true).order('weekday')
          end
      end

      # Send mail
      if send_mail && src_dataset_in_pool.dataset.user.mailer_enabled
        mail(:dataset_migration_begun, {
             user: dataset_user,
             vars: {
               dataset: src_dataset_in_pool.dataset,
               src_pool: src_pool,
               dst_pool: dst_pool,
               exports: exports.map(&:first),
               export_mounts:,
               vpses:,
               restart_vps:,
               maintenance_window: maintenance_windows,
               maintenance_windows:,
               custom_window: maintenance_windows && !finish_weekday.nil?,
               finish_weekday: finish_weekday,
               finish_minutes: finish_minutes,
               reason: reason
             }
           })
      end

      # Create datasets
      datasets.each do |pair|
        src, dst = pair

        # Transfer resources
        if environment_changed?
          # This code expects that the datasets have a just one cluster resource,
          # which is diskspace.
          changes = src.transfer_resources_to_env!(dataset_user, dst_node.location.environment)
          changes[changes.keys.first][:row_id] = dst.id
          resources_changes.update(changes)

        else
          ::ClusterResourceUse.for_obj(src).each do |use|
            resources_changes[use] = { row_id: dst.id }
          end
        end

        # Create datasets with canmount=off for the transfer
        append_t(Transactions::Storage::CreateDataset, args: [
                   dst,
                   { canmount: 'off' },
                   {
                     set_map: true,
                     create_private: false
                   }
                 ]) { |t| t.create(dst) }

        # Set all properties except for quotas to ensure send/recv will pass
        props = {}

        src.dataset_properties.where(inherited: false).each do |p|
          next if %w[quota refquota compressratio refcompressratio].include?(p.name)

          props[p.name.to_sym] = [p, p.value]
        end

        append(Transactions::Storage::SetDataset, args: [dst, props]) if props.any?
      end

      # Transfer datasets
      migration_snapshots = []

      # Reserve a slot in zfs_recv and zfs_send queue
      append(Transactions::Queue::Reserve, args: [src_node, :zfs_send])
      append(Transactions::Queue::Reserve, args: [dst_node, :zfs_recv])

      datasets.each do |pair|
        src, dst = pair

        migration_snapshots << use_chain(Dataset::Snapshot, args: src)
        use_chain(Dataset::Transfer, args: [src, dst])
      end

      # Maintenance window
      if maintenance_windows
        # Temporarily release the reserved spot in the queue, we'll get another
        # reservation within the maintenance window
        append(Transactions::Queue::Release, args: [dst_node, :zfs_recv])
        append(Transactions::Queue::Release, args: [src_node, :zfs_send])

        # Wait for the outage window to open
        append(
          Transactions::MaintenanceWindow::Wait,
          args: [nil, 15],
          kwargs: { maintenance_windows:, node: src_node }
        )
        append(Transactions::Queue::Reserve, args: [src_node, :zfs_send])
        append(Transactions::Queue::Reserve, args: [dst_node, :zfs_recv])
        append(
          Transactions::MaintenanceWindow::InOrFail,
          args: [nil, 15],
          kwargs: { maintenance_windows:, node: src_node }
        )

        # Intermediary transfer
        datasets.each do |pair|
          src, dst = pair

          migration_snapshots << use_chain(Dataset::Snapshot, args: src)
          use_chain(Dataset::Transfer, args: [src, dst])
        end

        # Check if we're still inside the outage window. We're in if the window
        # closes in not less than 5 minutes. Fail if not.
        append(
          Transactions::MaintenanceWindow::InOrFail,
          args: [nil, 5],
          kwargs: { maintenance_windows:, node: src_node },
          urgent: true
        )
      end

      # Stop affected VPS
      if restart_vps
        vpses.each do |vps|
          use_chain(Vps::Stop, args: [vps], urgent: true)
        end
      end

      # Stop exports
      exports.each do |pair|
        src_export, = pair

        if dst_pool.node_id == src_pool.node_id
          # In case of migration between two pools on the same node, the export must be
          # destroyed, because export names are global and future ::Create would fail.
          append_t(Transactions::Export::Destroy, args: [src_export, src_export.host_ip_address], urgent: true)
        else
          append_t(Transactions::Export::Disable, args: [src_export], urgent: true) do |t|
            t.edit(src_export, enabled: false)
          end
        end
      end

      # Final transfer
      datasets.each do |pair|
        src, dst = pair

        migration_snapshots << use_chain(Dataset::Snapshot, args: src, urgent: true)
        use_chain(Dataset::Transfer, args: [src, dst], urgent: true)
      end

      # Set quotas when all data is transfered
      datasets.each do |pair|
        src, dst = pair
        props = {}

        src.dataset_properties.where(inherited: false, name: %w[quota refquota]).each do |p|
          props[p.name.to_sym] = [p, p.value]
        end

        next unless props.any?

        append(
          Transactions::Storage::SetDataset,
          args: [dst, props],
          urgent: true,
          reversible: :keep_going # quota may be exceeded
        )
      end

      # Set canmount=on on all datasets
      append(
        Transactions::Storage::SetCanmount,
        args: [
          datasets.map { |_src, dst| dst }
        ],
        kwargs: {
          canmount: 'on',
          mount: true
        },
        urgent: true
      )

      # Create exports on dst pool
      exports.each do |pair|
        _, dst_export = pair

        append_t(Transactions::Export::Create, args: [dst_export, dst_export.host_ip_address], urgent: true) do |t|
          t.edit(dst_export, dataset_in_pool_id: dst_export.dataset_in_pool_id)
        end

        append_t(Transactions::Export::AddHosts, args: [dst_export, dst_export.export_hosts], urgent: true)

        next unless dst_export.enabled

        append_t(Transactions::Export::Enable, args: dst_export, urgent: true) do |t|
          t.edit(dst_export, enabled: true)
        end
      end

      # Restart VPS
      if restart_vps
        vpses.each do |vps|
          use_chain(Vps::Start, args: [vps], urgent: true) if vps.is_running?
        end
      end

      # Release reserved spots in the queue
      append(Transactions::Queue::Release, args: [dst_node, :zfs_recv])
      append(Transactions::Queue::Release, args: [src_node, :zfs_send])

      # Remove migration snapshots
      migration_snapshots.each do |sip|
        dst_sip = sip.snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
          dataset_in_pools: { pool_id: dst_pool.id }
        ).take!

        use_chain(SnapshotInPool::Destroy, args: dst_sip)
      end

      # Move the dataset in pool to the new pool in the database
      append_t(Transactions::Utils::NoOp, args: dst_node.id) do |t|
        # Transfer resources
        resources_changes.each do |use, changes|
          t.edit(use, changes) unless changes.empty?
        end

        # Handle dataset properties
        datasets.each do |src, dst|
          src.dataset_properties.all.each do |p|
            t.edit(p, dataset_in_pool_id: dst.id)
          end

          migrate_dataset_plans(src, dst, t)
        end
      end

      # Destroy exports on src pool
      if dst_pool.node_id != src_pool.node_id
        exports.each do |pair|
          src_export, = pair

          append_t(Transactions::Export::Destroy, args: [src_export, src_export.host_ip_address])
        end
      end

      # Destroy datasets on src
      use_chain(DatasetInPool::Destroy, args: [src_dataset_in_pool, {
        recursive: true,
        top: true,
        tasks: false,
        detach_backups: false,
        exports: false,
        destroy: cleanup_data
      }])

      # Send mail
      if send_mail && src_dataset_in_pool.dataset.user.mailer_enabled
        mail(:dataset_migration_finished, {
             user: dataset_user,
             vars: {
               dataset: src_dataset_in_pool.dataset,
               src_pool: src_pool,
               dst_pool: dst_pool,
               exports: exports.map(&:first),
               export_mounts:,
               vpses:,
               restart_vps:,
               maintenance_window: maintenance_windows,
               maintenance_windows:,
               custom_window: maintenance_windows && !finish_weekday.nil?,
               finish_weekday: finish_weekday,
               finish_minutes: finish_minutes,
               reason: reason
             }
           })
      end

      nil
    end

    protected

    attr_reader :src_node, :dst_node, :src_pool, :dst_pool, :maintenance_windows,
                :resources_changes

    def recursive_serialize(dataset, children)
      ret = []

      # First parents
      dip = dataset.dataset_in_pools.where(pool: src_pool).take
      return ret unless dip

      lock(dip)

      dst = ::DatasetInPool.create!(
        pool: dst_pool,
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
          dip = v.dataset_in_pools.where(pool: src_pool).take
          next unless dip

          lock(dip)

          dst = ::DatasetInPool.create!(
            pool: dst_pool,
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

    def environment_changed?
      src_node.location.environment_id != dst_node.location.environment_id
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
            environment: dst_dip.pool.node.location.environment
          ).user_add
        rescue ActiveRecord::RecordNotFound
          next # the plan is not present in the target environment
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
  end
end
