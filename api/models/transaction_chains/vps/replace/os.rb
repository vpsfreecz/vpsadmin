require_relative '../clone/base'
require 'securerandom'

module TransactionChains
  # Replace an unresponsive VPS with a new one
  class Vps::Replace::Os < ::TransactionChain
    label 'Replace'

    include Vps::Clone::Base

    def link_chain(vps, node, attrs)
      lock(vps)

      @src_pool = vps.dataset_in_pool.pool
      @dst_pool = ::Pool.take_by_node!(
        node,
        role: :hypervisor,
        required_diskspace: VpsAdmin::API::Operations::Utils::PoolSpace.required_dataset_tree_diskspace(
          vps.dataset_in_pool
        )
      )

      dst_features = {}
      vps_resources = nil
      confirm_features = []
      confirm_windows = []

      vps.vps_features.all.each do |f|
        dst_features[f.name.to_sym] = f.enabled
      end

      dst_vps = ::Vps.new(
        user_id: vps.user_id,
        hostname: vps.hostname,
        manage_hostname: vps.manage_hostname,
        dns_resolver_id: vps.dns_resolver_id,
        os_template_id: vps.os_template_id,
        info: "Replaced #{vps.id}. Original info:\n#{vps.info}",
        node_id: node.id,
        user_namespace_map: vps.user_namespace_map,
        map_mode: vps.map_mode,
        onstartall: vps.onstartall,
        cpu_limit: vps.cpu_limit,
        start_menu_timeout: vps.start_menu_timeout,
        cgroup_version: vps.cgroup_version,
        expiration_date: vps.expiration_date,
        allow_admin_modifications: vps.allow_admin_modifications,
        enable_os_template_auto_update: vps.enable_os_template_auto_update,
        enable_network: vps.enable_network,
        confirmed: ::Vps.confirmed(:confirm_create)
      )

      remote = dst_vps.node_id != vps.node_id

      check_cgroup_version!(dst_vps, node)

      dst_vps.save!
      lock(dst_vps)

      ::VpsFeature::FEATURES.each do |name, f|
        next unless f.support?(dst_vps.node)

        confirm_features << ::VpsFeature.create!(
          vps: dst_vps,
          name:,
          enabled: dst_features.fetch(name, false)
        )
      end

      # Maintenance windows
      vps.vps_maintenance_windows.each do |w|
        w = VpsMaintenanceWindow.new(
          vps: dst_vps,
          weekday: w.weekday,
          is_open: w.is_open,
          opens_at: w.opens_at,
          closes_at: w.closes_at
        )
        w.save!(validate: false)
        confirm_windows << w
      end

      # Allocate resources for the new VPS
      vps_resources = dst_vps.allocate_resources(
        required: %i[cpu memory swap],
        optional: [],
        user: dst_vps.user,
        chain: self,
        values: {
          cpu: vps.cpu,
          memory: vps.memory,
          swap: vps.swap
        },
        admin_override: true
      )

      dst_vps.dataset_in_pool = vps_dataset(vps, dst_vps, true)
      lock(dst_vps.dataset_in_pool)
      dst_vps.save!

      concerns(:transform, [vps.class.name, vps.id], [vps.class.name, dst_vps.id])

      # Stop the broken VPS
      append(Transactions::Vps::RecoverCleanup, args: [
               vps,
               { network_interfaces: true }
             ])

      # Free resources of the original VPS
      append_t(Transactions::Utils::NoOp, args: vps.node_id) do |t|
        # Mark all resources as disabled until they are really freed by
        # hard_delete. Revive should mark them back as enabled.
        objs = [vps, vps.dataset_in_pool]
        objs.concat(vps.dataset_in_pool.subdatasets_in_pool)

        objs.each do |obj|
          lock(obj)

          ::ClusterResourceUse.for_obj(obj).each do |use|
            lock(use.user_cluster_resource)
            t.edit(use, enabled: 0)
          end
        end
      end

      # Set state to soft_delete
      vps.record_object_state_change(
        :soft_delete,
        expiration: attrs[:expiration_date] || (Time.now + (60 * 24 * 60 * 60)),
        reason: "Replaced with VPS #{dst_vps.id}",
        chain: self
      )

      # Prepare userns
      use_chain(UserNamespaceMap::Use, args: [dst_vps, vps.user_namespace_map])

      # Datasets to clone
      datasets = serialize_datasets(vps.dataset_in_pool, dst_vps.dataset_in_pool)
      datasets.insert(0, [vps.dataset_in_pool, dst_vps.dataset_in_pool])

      prepare_backup_preservation(
        vps,
        dst_vps,
        datasets,
        attrs.fetch(:preserve_backups, true),
        attrs.fetch(:preserve_backup_history, true)
      )

      if remote
        token = SecureRandom.hex(6)

        # Authorize the migration
        append(
          Transactions::Pool::AuthorizeSendKey,
          args: [@dst_pool, @src_pool, dst_vps.id, "chain-#{id}-#{token}", token]
        )

        # Copy configs
        append(
          Transactions::Vps::SendConfig,
          args: [
            vps,
            node,
            @dst_pool
          ],
          kwargs: {
            as_id: dst_vps.id,
            network_interfaces: true,
            passphrase: token,
            snapshots: false,
            from_snapshot: osctld_from_snapshot
          }
        )

        # In case of rollback on the target node
        append(Transactions::Vps::SendRollbackConfig, args: dst_vps)
      end

      confirm_creation = proc do |t|
        datasets.each do |src, dst|
          t.create(dst_vps)

          confirm_features.each do |f|
            t.just_create(f)
          end

          confirm_windows.each do |w|
            t.just_create(w)
          end

          use = dst.allocate_resource!(
            :diskspace,
            src.diskspace,
            user: dst_vps.user,
            admin_override: true
          )

          properties = ::DatasetProperty.clone_properties!(src, dst)
          props_to_set = {}

          properties.each_value do |p|
            next if p.inherited

            props_to_set[p.name.to_sym] = p.value
          end

          t.create(dst.dataset)
          t.create(dst)
          t.create(use)

          properties.each_value do |p|
            t.create(p)
          end
        end
      end

      # Reserve a slot in zfs_send queue
      append(Transactions::Queue::Reserve, args: [vps.node, :zfs_send])

      if remote
        # Initial transfer
        append_t(Transactions::Vps::SendRootfs, args: [vps], &confirm_creation)
      else
        # Full copy
        append_t(
          Transactions::Vps::Copy,
          args: [
            vps,
            dst_vps.id,
            {
              consistent: false,
              network_interfaces: true,
              pool: @dst_pool,
              dataset: File.join(@dst_pool.filesystem, dst_vps.dataset_in_pool.dataset.full_name),
              from_snapshot: osctld_from_snapshot
            }
          ],
          &confirm_creation
        )
      end

      # Invoke dataset creation hooks and clone dataset plans
      datasets.each do |src, dst|
        # Invoke dataset create hook
        dst.call_class_hooks_for(
          :create,
          self,
          args: [dst],
          kwargs: {
            purpose: :vps_replace,
            source_dataset_in_pool: src,
            preserve_existing_backups: preserving_backup_path?(src)
          }
        )

        # Clone dataset plans
        clone_dataset_plans(src, dst) unless preserving_backup_path?(src)

        # Clone dataset expansions
        clone_dataset_expansions(src, dst, dst_vps)
      end

      if remote
        # Finish the transfer
        append_t(
          Transactions::Vps::SendState,
          args: [vps],
          kwargs: {
            clone: true,
            consistent: false,
            restart: false,
            start: false
          }
        )
      end

      # Release reserved spot in the queue
      append(Transactions::Queue::Release, args: [vps.node, :zfs_send])

      finish_backup_preservation(datasets)

      # Switch-over network interfaces
      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        vps.network_interfaces.each do |n|
          t.edit(n, vps_id: dst_vps.id)
        end
      end

      # Populate config of the new VPS
      append(
        Transactions::Vps::PopulateConfig,
        args: [dst_vps],
        kwargs: {
          pool: @dst_pool,
          network_interfaces: vps.network_interfaces.all
        }
      )

      # Resources
      use_chain(Vps::SetResources, args: [dst_vps, vps_resources])

      # Mounts
      clone_mounts(vps, dst_vps, datasets) do |mnt|
        # Remove all mounts except those of subdatasets
        dst_vps.dataset_in_pool_id == mnt.dataset_in_pool_id \
          || dst_vps.dataset_in_pool.dataset.ancestor_of?(mnt.dataset_in_pool.dataset)
      end

      if remote
        # Cleanup on the source node
        append(Transactions::Vps::SendCleanup, args: vps)
      end

      # Remove network interfaces from the old vps
      vps.network_interfaces.each do |n|
        append(Transactions::Vps::RemoveVeth, args: n)
      end

      # Prevent the old vps to autostart
      append(
        Transactions::Vps::Autostart,
        args: [vps],
        kwargs: { enable: false, revert: false }
      )

      # Start the new VPS
      use_chain(Vps::Start, args: dst_vps, reversible: :keep_going) if attrs[:start]

      dst_vps.save!

      if vps.user.mailer_enabled
        mail(:vps_replaced, {
          user: vps.user,
          vars: {
            original_vps: vps,
            new_vps: dst_vps,
            reason: attrs[:reason]
          }
        })
      end

      dst_vps
    end

    def prepare_backup_preservation(vps, dst_vps, datasets, preserve_backups, preserve_history)
      @replace_preserve_backups = preserve_backups
      @replace_preserve_history = preserve_backups && preserve_history
      @replace_backup_dips = {}
      @replace_snapshot_sips = {}

      return unless preserve_backups

      datasets.map(&:first).each do |src|
        backup_dips = backup_dips_for(src).to_a
        backup_dips.each { |dip| lock(dip) }
        @replace_backup_dips[src.id] = backup_dips
      end
      @replace_backup_root_dips = topmost_dips(@replace_backup_dips.values.flatten)

      return unless @replace_preserve_history

      snap_label = "Created for VPS replace #{vps.id} -> #{dst_vps.id}"
      snapshot_sips = use_chain(
        Dataset::GroupSnapshot,
        args: [datasets.map(&:first)],
        kwargs: {
          label: snap_label,
          strict: true
        }
      )

      snapshot_sips.each do |sip|
        @replace_snapshot_sips[sip.dataset_in_pool_id] = sip
      end
      @replace_root_snapshot = snapshot_sips.first.snapshot

      datasets.map(&:first).each do |src|
        @replace_backup_dips.fetch(src.id).each do |backup_dip|
          use_chain(
            Dataset::Transfer,
            args: [src, backup_dip],
            kwargs: { send_reservation: true }
          )
        end
      end
    end

    def finish_backup_preservation(datasets)
      return unless @replace_preserve_backups

      backup_rewrites = backup_rewrite_entries(datasets)

      if @replace_preserve_history
        datasets.each do |src, dst|
          confirm_replacement_snapshot(dst, @replace_snapshot_sips.fetch(src.id))
        end
      end

      assert_no_replacement_backup_dips!(backup_rewrites)
      rename_backup_datasets(backup_rewrites)
      confirm_backup_preservation(datasets, backup_rewrites)
    end

    def backup_dips_for(dataset_in_pool)
      dataset_in_pool.dataset.dataset_in_pools
                     .joins(:pool)
                     .where(pools: { role: ::Pool.roles[:backup] })
                     .where.not(confirmed: ::DatasetInPool.confirmed(:confirm_destroy))
    end

    def preserving_backup_dips?(dataset_in_pool)
      @replace_backup_dips && @replace_backup_dips.fetch(dataset_in_pool.id, []).any?
    end

    def backup_rewrite_entries(datasets)
      datasets.flat_map do |src, dst|
        @replace_backup_dips.fetch(src.id).map do |backup_dip|
          {
            src:,
            dst:,
            backup: backup_dip
          }
        end
      end
    end

    def replacement_backup_dip(dst_dip, pool)
      dip = dst_dip.dataset.dataset_in_pools
                   .where(pool:)
                   .where.not(confirmed: ::DatasetInPool.confirmed(:confirm_destroy))
                   .take

      dip if dip && dip.id != dst_dip.id
    end

    def preserving_backup_path?(dataset_in_pool)
      return false unless @replace_backup_root_dips

      @replace_backup_root_dips.any? do |backup_dip|
        backup_dip.dataset_id == dataset_in_pool.dataset_id ||
          backup_dip.dataset.ancestor_of?(dataset_in_pool.dataset)
      end
    end

    def osctld_from_snapshot
      @replace_root_snapshot if @replace_preserve_history
    end

    def confirm_replacement_snapshot(dst, snapshot_in_pool)
      append(
        Transactions::Storage::RecvCheck,
        args: [dst, [snapshot_in_pool]]
      ) do
        sip = ::SnapshotInPool.where(
          snapshot_id: snapshot_in_pool.snapshot_id,
          dataset_in_pool: dst
        ).where.not(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy)).take
        next if sip

        create(::SnapshotInPool.create!(
                 snapshot_id: snapshot_in_pool.snapshot_id,
                 dataset_in_pool: dst,
                 confirmed: ::SnapshotInPool.confirmed(:confirm_create)
               ))
      end
    end

    def assert_no_replacement_backup_dips!(backup_rewrites)
      conflicts = replacement_backup_conflicts(backup_rewrites)
      return if conflicts.empty?

      descriptions = conflicts.map do |dip|
        "#{dip.id} (#{dip.pool.filesystem}/#{dip.dataset.full_name})"
      end.join(', ')

      raise "replacement backup dataset already exists: #{descriptions}. " \
            'DatasetInPool.create hooks must skip backup provisioning when ' \
            'purpose is :vps_replace and preserve_existing_backups is true.'
    end

    def replacement_backup_conflicts(backup_rewrites)
      backup_rewrites.flat_map do |entry|
        replacement_backup_dips_in_subtree(entry.fetch(:dst), entry.fetch(:backup).pool)
      end.uniq
    end

    def replacement_backup_dips_in_subtree(dst_dip, pool)
      ::DatasetInPool
        .where(pool:)
        .where(dataset_id: dst_dip.dataset.subtree.select(:id))
        .where.not(confirmed: ::DatasetInPool.confirmed(:confirm_destroy))
        .to_a
    end

    def rename_backup_datasets(backup_rewrites)
      topmost_dips(backup_rewrites.map { |entry| entry[:backup] }).each do |backup_dip|
        dst = backup_rewrites.detect { |entry| entry[:backup].id == backup_dip.id }.fetch(:dst)

        append(
          Transactions::Storage::RenameDataset,
          args: [
            backup_dip.pool,
            backup_dip.dataset.full_name,
            dst.dataset.full_name
          ]
        )
      end
    end

    def confirm_backup_preservation(datasets, backup_rewrites)
      snapshot_name_clones = {}

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        destroyed_plans = {}
        destroyed_actions = {}
        destroyed_tasks = {}
        destroyed_groups = {}
        edited_group_actions = {}

        datasets.each do |src, dst|
          moved_by_pool = backup_rewrites.select { |entry| entry[:src].id == src.id }.to_h do |entry|
            [entry[:backup].pool_id, entry[:backup]]
          end

          snapshot_replacements = replacement_snapshots(t, src, dst, moved_by_pool.values, snapshot_name_clones)

          if @replace_preserve_history
            t.edit(dst.dataset, current_history_id: src.dataset.current_history_id)
          end

          moved_by_pool.each_value do |backup_dip|
            t.edit(backup_dip, dataset_id: dst.dataset_id)
          end

          reassign_snapshot_in_pools(t, dst, moved_by_pool.values, snapshot_replacements)
          reassign_dataset_plans(
            t,
            src,
            dst,
            moved_by_pool,
            destroyed_plans,
            destroyed_actions,
            destroyed_tasks
          )
          reassign_group_snapshots(
            t,
            src,
            dst,
            destroyed_actions,
            destroyed_tasks,
            destroyed_groups,
            edited_group_actions
          )
        end
      end

      return if snapshot_name_clones.empty?

      append(
        Transactions::Storage::CloneSnapshotName,
        args: [@dst_pool.node, snapshot_name_clones]
      )
    end

    def replacement_snapshots(t, src, dst, backup_dips, snapshot_name_clones)
      snapshots = snapshots_to_preserve(src, backup_dips)
      source_snapshot_ids = src.snapshot_in_pools
                               .where(snapshot_id: snapshots.keys)
                               .where.not(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
                               .pluck(:snapshot_id)

      snapshots.to_h do |snapshot_id, snapshot|
        if source_snapshot_ids.include?(snapshot_id)
          replacement = clone_snapshot_for_replacement(t, snapshot, dst)
          track_snapshot_name_clone(snapshot_name_clones, snapshot, replacement)
          [snapshot_id, replacement]
        else
          t.edit(snapshot, dataset_id: dst.dataset_id)
          [snapshot_id, snapshot]
        end
      end
    end

    def snapshots_to_preserve(src, backup_dips)
      snapshots = {}

      backup_dips.each do |backup_dip|
        backup_dip.snapshot_in_pools
                  .where.not(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
                  .includes(:snapshot)
                  .each do |sip|
          snapshots[sip.snapshot_id] = sip.snapshot
        end
      end

      if @replace_preserve_history
        replace_snapshot = @replace_snapshot_sips.fetch(src.id).snapshot
        snapshots[replace_snapshot.id] = replace_snapshot
      end

      snapshots
    end

    def clone_snapshot_for_replacement(t, snapshot, dst)
      replacement = ::Snapshot.create!(
        name: snapshot.name,
        dataset_id: dst.dataset_id,
        history_id: snapshot.history_id,
        label: snapshot.label,
        created_at: snapshot.created_at,
        confirmed: ::Snapshot.confirmed(:confirm_create)
      )
      t.create(replacement)
      replacement
    end

    def track_snapshot_name_clone(clones, snapshot, replacement)
      clones[snapshot.id] = [
        replacement.name,
        replacement.created_at.utc.strftime('%Y-%m-%d %H:%M:%S'),
        replacement.id
      ]
    end

    def reassign_snapshot_in_pools(t, dst, backup_dips, snapshot_replacements)
      backup_dips.each do |backup_dip|
        reassign_snapshot_in_pool_refs(t, backup_dip, snapshot_replacements)
      end

      reassign_snapshot_in_pool_refs(t, dst, snapshot_replacements)
    end

    def reassign_snapshot_in_pool_refs(t, dataset_in_pool, snapshot_replacements)
      dataset_in_pool.snapshot_in_pools
                     .where(snapshot_id: snapshot_replacements.keys)
                     .where.not(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
                     .each do |sip|
        replacement = snapshot_replacements.fetch(sip.snapshot_id)
        next if replacement.id == sip.snapshot_id

        t.edit(sip, snapshot_id: replacement.id)
      end
    end

    def reassign_dataset_plans(t, src, dst, moved_by_pool, destroyed_plans, destroyed_actions, destroyed_tasks)
      src.dataset_in_pool_plans.includes(:environment_dataset_plan, :dataset_actions).each do |plan|
        dst_env_plan = ::EnvironmentDatasetPlan.find_by(
          environment: dst.pool.node.location.environment,
          dataset_plan_id: plan.environment_dataset_plan.dataset_plan_id
        )

        unless dst_env_plan
          destroy_dataset_plan(t, plan, destroyed_plans, destroyed_actions, destroyed_tasks)
          next
        end

        ::DatasetInPoolPlan.where(
          dataset_in_pool: dst,
          environment_dataset_plan: dst_env_plan
        ).where.not(id: plan.id).each do |dst_plan|
          destroy_dataset_plan(t, dst_plan, destroyed_plans, destroyed_actions, destroyed_tasks)
        end

        t.edit(
          plan,
          dataset_in_pool_id: dst.id,
          environment_dataset_plan_id: dst_env_plan.id
        )

        plan.dataset_actions.each do |action|
          next unless action.backup?

          backup_dip = moved_by_pool[action.dst_dataset_in_pool.pool_id] ||
                       replacement_backup_dip(dst, action.dst_dataset_in_pool.pool)
          next unless backup_dip

          t.edit(
            action,
            src_dataset_in_pool_id: dst.id,
            dst_dataset_in_pool_id: backup_dip.id
          )
        end
      end
    end

    def destroy_dataset_plan(t, plan, destroyed_plans, destroyed_actions, destroyed_tasks)
      return if destroyed_plans[plan.id]

      plan.dataset_actions.each do |action|
        destroy_dataset_action(t, action, destroyed_actions, destroyed_tasks)
      end

      t.just_destroy(plan)
      destroyed_plans[plan.id] = true
    end

    def destroy_dataset_action(t, action, destroyed_actions, destroyed_tasks)
      return if destroyed_actions[action.id]

      task = ::RepeatableTask.find_for(action)
      if task && !destroyed_tasks[task.id]
        t.just_destroy(task)
        destroyed_tasks[task.id] = true
      end

      t.just_destroy(action)
      destroyed_actions[action.id] = true
    end

    def reassign_group_snapshots(t, src, dst, destroyed_actions, destroyed_tasks, destroyed_groups,
                                 edited_group_actions)
      src.group_snapshots.includes(:dataset_action).each do |group|
        action = group.dataset_action

        ::DatasetAction.where(
          pool_id: dst.pool_id,
          action: ::DatasetAction.actions[:group_snapshot],
          dataset_plan_id: action.dataset_plan_id
        ).where.not(id: action.id).each do |dst_action|
          destroy_group_snapshot_action(t, dst_action, destroyed_actions, destroyed_tasks, destroyed_groups)
        end

        t.edit(group, dataset_in_pool_id: dst.id)

        next if edited_group_actions[action.id]

        t.edit(action, pool_id: dst.pool_id)
        edited_group_actions[action.id] = true
      end
    end

    def destroy_group_snapshot_action(t, action, destroyed_actions, destroyed_tasks, destroyed_groups)
      action.group_snapshots.each do |group|
        next if destroyed_groups[group.id]

        t.just_destroy(group)
        destroyed_groups[group.id] = true
      end

      destroy_dataset_action(t, action, destroyed_actions, destroyed_tasks)
    end

    def topmost_dips(dips)
      dips.uniq.reject do |dip|
        dips.any? do |other|
          other.id != dip.id && other.dataset.ancestor_of?(dip.dataset)
        end
      end
    end

    # Create a new dataset for target VPS.
    def vps_dataset(vps, dst_vps, _clone_plans)
      ds = ::Dataset.new(
        name: dst_vps.id.to_s,
        user: dst_vps.user,
        vps: dst_vps,
        user_editable: true,
        user_create: true,
        user_destroy: false,
        confirmed: ::Dataset.confirmed(:confirm_create)
      )

      ::DatasetInPool.create!(
        pool: @dst_pool,
        dataset: ds,
        label: "vps#{dst_vps.id}",
        min_snapshots: vps.dataset_in_pool.min_snapshots,
        max_snapshots: vps.dataset_in_pool.max_snapshots,
        snapshot_max_age: vps.dataset_in_pool.snapshot_max_age
      )
    end

    def serialize_datasets(dataset_in_pool, dst_dataset_in_pool)
      ret = []

      dataset_in_pool.dataset.descendants.arrange.each do |k, v|
        ret.concat(recursive_serialize(k, v, dst_dataset_in_pool.dataset))
      end

      ret
    end

    def recursive_serialize(dataset, children, parent)
      ret = []

      # First parents
      dip = dataset.dataset_in_pools.where(pool: @src_pool).take

      return ret unless dip

      lock(dip)

      ds = ::Dataset.create!(
        parent:,
        name: dip.dataset.name,
        user: dip.dataset.user,
        vps: parent.vps,
        user_editable: dip.dataset.user_editable,
        user_create: dip.dataset.user_create,
        user_destroy: dip.dataset.user_destroy,
        confirmed: ::Dataset.confirmed(:confirm_create)
      )

      parent = ds

      dst = ::DatasetInPool.create!(
        pool: @dst_pool,
        dataset: ds,
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

          ds = ::Dataset.create!(
            parent:,
            name: dip.dataset.name,
            user: dip.dataset.user,
            vps: parent.vps,
            user_editable: dip.dataset.user_editable,
            user_create: dip.dataset.user_create,
            user_destroy: dip.dataset.user_destroy,
            confirmed: ::Dataset.confirmed(:confirm_create)
          )

          dst = ::DatasetInPool.create!(
            pool: @dst_pool,
            dataset_id: ds,
            label: dip.label,
            min_snapshots: dip.min_snapshots,
            max_snapshots: dip.max_snapshots,
            snapshot_max_age: dip.snapshot_max_age
          )

          lock(dst)

          ret << [dip, dst]

        else
          ret.concat(recursive_serialize(k, v, parent))
        end
      end

      ret
    end

    def check_cgroup_version!(vps, dst_node)
      check_v =
        if vps.cgroup_version == 'cgroup_any'
          vps.os_template.cgroup_version
        else
          vps.cgroup_version
        end

      return if check_v == 'cgroup_any'

      if check_v == 'cgroup_v1' && dst_node.cgroup_version != check_v
        raise VpsAdmin::API::Exceptions::OperationNotSupported,
              "VPS requires cgroup v1 and #{dst_node.domain_name} has cgroup v2"

      elsif check_v == 'cgroup_v2' && dst_node.cgroup_version != check_v
        raise VpsAdmin::API::Exceptions::OperationNotSupported,
              "VPS requires cgroup v2 and #{dst_node.domain_name} has cgroup v1"
      end
    end
  end
end
