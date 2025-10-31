require_relative 'base'
require 'securerandom'

module TransactionChains
  # Clone VPS to new or another VPS.
  class Vps::Clone::OsToOs < ::TransactionChain
    label 'Clone'

    include Vps::Clone::Base

    def link_chain(vps, node, attrs)
      lock(vps)

      # When cloning to a new VPS:
      # - Create datasets - clone properties
      # - Create vz root
      # - Copy config
      # - Allocate resources (default or the same)
      # - Clone mounts (generate action scripts, snapshot mount references)
      # - Transfer data (one or two runs depending on attrs[stop])
      # - Set features

      # When cloning into another VPS:
      # - Transfer all local snapshots to the backup
      # - Stop target VPS
      # - Destroy all datasets
      # - Reallocate resources if attrs[resources]
      # - Continue the process as above, except creating vz root

      check_cgroup_version!(vps, node)

      @src_pool = vps.dataset_in_pool.pool
      @dst_pool = ::Pool.take_by_node!(node, role: :hypervisor)

      dst_features = {}
      vps_resources = nil
      confirm_features = []
      confirm_windows = []
      token = SecureRandom.hex(6)

      if attrs[:features]
        vps.vps_features.all.each do |f|
          dst_features[f.name.to_sym] = f.enabled
        end
      end

      @userns_map = if attrs[:user] == vps.user
                      nil
                    else
                      ::UserNamespaceMap.joins(:user_namespace).where(
                        user_namespaces: { user_id: attrs[:user].id }
                      ).take!
                    end

      dst_vps = ::Vps.new(
        user_id: attrs[:user].id,
        hostname: attrs[:hostname],
        manage_hostname: vps.manage_hostname,
        operating_system_id: vps.operating_system_id,
        os_template_id: vps.os_template_id,
        info: "Cloned from #{vps.id}. Original info:\n#{vps.info}",
        node_id: node.id,
        user_namespace_map: @userns_map || vps.user_namespace_map,
        map_mode: vps.map_mode,
        onstartall: vps.onstartall,
        cpu_limit: attrs[:resources] ? vps.cpu_limit : nil,
        start_menu_timeout: vps.start_menu_timeout,
        cgroup_version: vps.cgroup_version,
        allow_admin_modifications: vps.allow_admin_modifications,
        enable_os_template_auto_update: vps.enable_os_template_auto_update,
        enable_network: vps.enable_network,
        confirmed: ::Vps.confirmed(:confirm_create)
      )

      remote = dst_vps.node_id != vps.node_id

      lifetime = dst_vps.user.env_config(
        dst_vps.node.location.environment,
        :vps_lifetime
      )

      dst_vps.expiration_date = Time.now + lifetime if lifetime != 0

      dst_vps.save!
      lock(dst_vps)

      ::VpsFeature::FEATURES.each do |name, f|
        next unless f.support?(dst_vps.node)

        confirm_features << ::VpsFeature.create!(
          vps: dst_vps,
          name:,
          enabled: attrs[:features] && f.support?(vps.node) ? dst_features[name] : false
        )
      end

      # Maintenance windows
      # FIXME: user could choose if he wants to clone it
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

      # FIXME: do not fail when there are insufficient resources.
      # It is ok when the available resource is higher than minimum.
      # Perhaps make it a boolean attribute determining if resources
      # must be allocated all or if the available number is sufficient.
      vps_resources = dst_vps.allocate_resources(
        required: %i[cpu memory swap],
        optional: [],
        user: dst_vps.user,
        chain: self,
        values: if attrs[:resources]
                  {
                    cpu: vps.cpu,
                    memory: vps.memory,
                    swap: vps.swap
                  }
                else
                  {}
                end
      )

      dst_vps.dataset_in_pool = vps_dataset(vps, dst_vps, attrs[:dataset_plans])
      lock(dst_vps.dataset_in_pool)
      dst_vps.save!

      concerns(:transform, [vps.class.name, vps.id], [vps.class.name, dst_vps.id])

      # Prepare userns
      use_chain(UserNamespaceMap::Use, args: [dst_vps, vps.user_namespace_map])

      # When cloning to a different user, we first send it with the original
      # mapping and then chown it on the target node and remove the original
      # mapping.
      use_chain(UserNamespaceMap::Use, args: [dst_vps, @userns_map]) if @userns_map

      if remote
        # Authorize the migration
        append(
          Transactions::Pool::AuthorizeSendKey,
          args: [@dst_pool, @src_pool, dst_vps.id, "chain-#{id}-#{token}", token]
        )

        # Initiate clone
        append(
          Transactions::Vps::SendConfig,
          args: [
            vps,
            node,
            @dst_pool
          ],
          kwargs: {
            as_id: dst_vps.id,
            network_interfaces: false,
            snapshots: false,
            passphrase: token
          }
        )

        # In case of rollback on the target node
        append(Transactions::Vps::SendRollbackConfig, args: dst_vps)
      end

      # Datasets to clone
      datasets = serialize_datasets(vps.dataset_in_pool, dst_vps.dataset_in_pool)
      datasets.insert(0, [vps.dataset_in_pool, dst_vps.dataset_in_pool])

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
            user: dst_vps.user
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
      append(Transactions::Queue::Reserve, args: [dst_vps.node, :zfs_recv])

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
            { consistent: attrs[:stop], network_interfaces: false, pool: @dst_pool }
          ],
          &confirm_creation
        )
      end

      # Invoke dataset creation hooks and clone dataset plans
      datasets.each do |src, dst|
        # Invoke dataset create hook
        dst.call_class_hooks_for(:create, self, args: [dst])

        # Clone dataset plans
        clone_dataset_plans(src, dst) if attrs[:dataset_plans]

        # Clone dataset expansions
        clone_dataset_expansions(src, dst, dst_vps)
      end

      if remote
        # Make a second transfer if requested
        if attrs[:stop]
          use_chain(Vps::Stop, args: vps)
          append(Transactions::Vps::SendSync, args: [vps], urgent: true)
          use_chain(Vps::Start, args: vps, urgent: true) if vps.running?
        end

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
      append(Transactions::Queue::Release, args: [dst_vps.node, :zfs_recv])
      append(Transactions::Queue::Release, args: [vps.node, :zfs_send])

      # Chown the VPS if needed
      if @userns_map
        append_t(Transactions::Vps::Chown, args: [
                   dst_vps,
                   vps.user_namespace_map,
                   @userns_map
                 ])

        # Release the original osctl user
        use_chain(
          UserNamespaceMap::Disuse,
          args: [dst_vps],
          kwargs: { userns_map: vps.user_namespace_map }
        )
      end

      # Hostname
      clone_hostname(vps, dst_vps, attrs)

      # Resources
      use_chain(Vps::SetResources, args: [dst_vps, vps_resources]) if vps_resources

      # IP addresses
      clone_network_interfaces(vps, dst_vps, attrs) unless attrs[:vps]

      # DNS resolver
      dst_vps.dns_resolver = dns_resolver(vps, dst_vps)
      clone_dns_resolver(vps, dst_vps)

      # Mounts
      clone_mounts(vps, dst_vps, datasets) do |mnt|
        # Remove all mounts except those of subdatasets
        dst_vps.dataset_in_pool_id == mnt.dataset_in_pool_id \
          || dst_vps.dataset_in_pool.dataset.ancestor_of?(mnt.dataset_in_pool.dataset)
      end

      # Features
      append(Transactions::Vps::Features, args: [dst_vps, confirm_features]) do
        if attrs[:vps]
          dst_vps.vps_features.each do |f|
            edit(f, enabled: dst_features[f.name.to_sym] ? 1 : 0)
          end
        end
      end

      # Start the new VPS
      use_chain(TransactionChains::Vps::Start, args: dst_vps) if vps.running?

      if remote
        # Cleanup on the source node
        append(Transactions::Vps::SendCleanup, args: vps)
      end

      dst_vps.save!
      dst_vps
    end

    # Create a new dataset for target VPS.
    def vps_dataset(vps, dst_vps, _clone_plans)
      ds = ::Dataset.new(
        name: dst_vps.id.to_s,
        user: dst_vps.user,
        vps: dst_vps,
        user_editable: false,
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

    def clone_network_interfaces(vps, dst_vps, attrs)
      sums = {
        ipv4: 0,
        ipv4_private: 0,
        ipv6: 0
      }

      # Allocate addresses to interfaces
      vps.network_interfaces.each do |netif|
        dst_netif = use_chain(
          NetworkInterface.chain_for(netif.kind, :Clone),
          args: [netif, dst_vps]
        )

        sums.merge!(clone_ip_addresses(netif, dst_netif, attrs)) do |_key, old_val, new_val|
          old_val + new_val
        end
      end

      # Reallocate cluster resources
      user_env = dst_vps.user.environment_user_configs.find_by!(
        environment: dst_vps.node.location.environment
      )

      changes = sums.map do |r, sum|
        user_env.reallocate_resource!(
          r,
          user_env.send(r) + sum,
          user: dst_vps.user,
          chain: self,
          confirmed: ::ClusterResourceUse.confirmed(:confirmed)
        )
      end

      return unless changes.any?

      append_t(Transactions::Utils::NoOp, args: dst_vps.node_id) do |t|
        changes.each { |use| t.edit(use, { value: use.value }) }
      end
    end

    # Clone IP addresses.
    # Allocates the equal number (or how many are available) of
    # IP addresses.
    def clone_ip_addresses(netif, dst_netif, attrs)
      ips = {
        ipv4: netif.ip_addresses.joins(:network).where(
          networks: {
            ip_version: 4,
            role: ::Network.roles[:public_access]
          }
        ).count,

        ipv4_private: netif.ip_addresses.joins(:network).where(
          networks: {
            ip_version: 4,
            role: ::Network.roles[:private_access]
          }
        ).count,

        ipv6: netif.ip_addresses.joins(:network).where(
          networks: { ip_version: 6 }
        ).count
      }

      versions = %i[ipv4 ipv4_private]
      versions << :ipv6 if dst_netif.vps.node.location.has_ipv6

      ret = {}

      versions.each do |r|
        chowned = use_chain(
          Ip::Allocate,
          args: [
            ::ClusterResource.find_by!(name: r),
            dst_netif,
            ips[r]
          ],
          kwargs: {
            strict: false,
            host_addrs: true,
            address_location: attrs[:address_location]
          },
          method: :allocate_to_netif
        )

        ret[r] = chowned
      end

      ret
    end
  end
end
