require_relative '../clone/base'

module TransactionChains
  # Replace an unresponsive VPS with a new one
  class Vps::Replace::Os < ::TransactionChain
    label 'Replace'

    include Vps::Clone::Base

    def link_chain(vps, node, attrs)
      lock(vps)

      @src_pool = vps.dataset_in_pool.pool
      @dst_pool = node.pools.where(role: ::Pool.roles[:hypervisor]).take!

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
        onboot: vps.onboot,
        onstartall: vps.onstartall,
        config: vps.config,
        cpu_limit: vps.cpu_limit,
        expiration_date: vps.expiration_date,
        confirmed: ::Vps.confirmed(:confirm_create),
      )

      remote = dst_vps.node_id != vps.node_id

      dst_vps.save!
      lock(dst_vps)

      ::VpsFeature::FEATURES.each do |name, f|
        next unless f.support?(dst_vps.node)

        confirm_features << ::VpsFeature.create!(
          vps: dst_vps,
          name: name,
          enabled: dst_features[name],
        )
      end

      # Maintenance windows
      vps.vps_maintenance_windows.each do |w|
        w = VpsMaintenanceWindow.new(
          vps: dst_vps,
          weekday: w.weekday,
          is_open: w.is_open,
          opens_at: w.opens_at,
          closes_at: w.closes_at,
        )
        w.save!(validate: false)
        confirm_windows << w
      end

      # Allocate resources for the new VPS
      vps_resources = dst_vps.allocate_resources(
        required: %i(cpu memory swap),
        optional: [],
        user: dst_vps.user,
        chain: self,
        values: {
          cpu: vps.cpu,
          memory: vps.memory,
          swap: vps.swap
        },
        admin_override: true,
      )

      dst_vps.dataset_in_pool = vps_dataset(vps, dst_vps, true)
      lock(dst_vps.dataset_in_pool)
      dst_vps.save!

      concerns(:transform, [vps.class.name, vps.id], [vps.class.name, dst_vps.id])

      # Stop the broken VPS
      append(Transactions::Vps::RecoverCleanup, args: [
        vps,
        network_interfaces: true,
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
        expiration: attrs[:expiration_date] || (Time.now + 60*24*60*60),
        reason: "Replaced with VPS #{dst_vps.id}",
        chain: self,
      )

      # Prepare userns
      use_chain(UserNamespaceMap::Use, args: [vps.userns_map, dst_vps.node])

      if remote
        append(
          Transactions::Vps::SendConfig,
          args: [vps, node, as_id: dst_vps.id, network_interfaces: true]
        )
      end

      # Datasets to clone
      datasets = serialize_datasets(vps.dataset_in_pool, dst_vps.dataset_in_pool)
      datasets.insert(0, [vps.dataset_in_pool, dst_vps.dataset_in_pool])

      confirm_creation = Proc.new do |t|
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
            admin_override: true,
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

      if remote
        # Initial transfer
        append_t(Transactions::Vps::SendRootfs, args: [vps], &confirm_creation)
      else
        # Full copy
        append_t(
          Transactions::Vps::Copy,
          args: [vps, dst_vps.id, consistent: false, network_interfaces: true],
          &confirm_creation
        )
      end

      # Invoke dataset creation hooks and clone dataset plans
      datasets.each do |src, dst|
        # Invoke dataset create hook
        dst.call_class_hooks_for(:create, self, args: [dst])

        # Clone dataset plans
        clone_dataset_plans(src, dst)
      end

      if remote
        # Finish the transfer
        append_t(
          Transactions::Vps::SendState,
          args: [vps, clone: true, consistent: false, restart: false, start: false],
        )
      end

      # Switch-over network interfaces
      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        vps.network_interfaces.each do |n|
          t.edit(n, vps_id: dst_vps.id)
        end
      end

      # Populate config of the new VPS
      append(Transactions::Vps::PopulateConfig, args: [
        dst_vps,
        network_interfaces: vps.network_interfaces.all,
      ])

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
      append(Transactions::Vps::Autostart, args: [vps, enable: false, revert: false])

      # Start the new VPS
      if attrs[:start]
        use_chain(Vps::Start, args: dst_vps, reversible: :keep_going)
      end

      if remote
        # Add IPS to accounting and shaper on the destination node
        vps.ip_addresses.each do |ip|
          append(Transactions::Firewall::RegIp, ip, dst_vps)
          append(Transactions::Shaper::Set, dst_vps, ip)
        end

        # Remove IPs from accounting and shaper on the source node
        vps.ip_addresses.each do |ip|
          append(Transactions::Firewall::UnregIp, ip, vps)
          append(Transactions::Shaper::Unset, vps, ip)
        end
      end

      dst_vps.save!
      dst_vps
    end

    # Create a new dataset for target VPS.
    def vps_dataset(vps, dst_vps, clone_plans)
      ds = ::Dataset.new(
        name: dst_vps.id.to_s,
        user: dst_vps.user,
        user_editable: false,
        user_create: true,
        user_destroy: false,
        confirmed: ::Dataset.confirmed(:confirm_create)
      )

      dip = ::DatasetInPool.create!(
        pool: @dst_pool,
        dataset: ds,
        label: "vps#{dst_vps.id}",
        min_snapshots: vps.dataset_in_pool.min_snapshots,
        max_snapshots: vps.dataset_in_pool.max_snapshots,
        snapshot_max_age: vps.dataset_in_pool.snapshot_max_age,
        user_namespace_map: vps.dataset_in_pool.user_namespace_map,
      )

      dip
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
        parent: parent,
        name: dip.dataset.name,
        user: dip.dataset.user,
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
        snapshot_max_age: dip.snapshot_max_age,
        user_namespace_map: dip.user_namespace_map,
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
            parent: parent,
            name: dip.dataset.name,
            user: dip.dataset.user,
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
            snapshot_max_age: dip.snapshot_max_age,
            user_namespace_map: dip.user_namespace_map,
          )

          lock(dst)

          ret << [dip, dst]

        else
          ret.concat(recursive_serialize(k, v, parent))
        end
      end

      ret
    end
  end
end
