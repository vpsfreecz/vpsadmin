require_relative 'base'
require_relative '../vz_to_os'

module TransactionChains
  # Migrate VPS from OpenVZ to vpsAdminOS node
  class Vps::Migrate::VzToOs < Vps::Migrate::Base
    label 'Migrate'

    include Vps::VzToOs

    def link_chain(vps, dst_node, opts = {})
      # TODO: configurable userns map
      self.userns_map = ::UserNamespaceMap.joins(:user_namespace).where(
        user_namespaces: {user_id: vps.user_id}
      ).take!

      # Process options
      setup(vps, dst_node, opts)
      dst_vps.os_template = replace_os_template(src_vps.os_template)

      # Check swap is available on the destination node
      check_swap!

      # Mail notification
      notify_begun

      # Transfer resources if the destination node is in a different
      # environment.
      transfer_cluster_resources

      # User namespace map
      use_chain(UserNamespaceMap::Use, args: [userns_map, dst_pool])

      # Create datasets
      datasets.each do |pair|
        src, dst = pair

        # Transfer resources
        if environment_changed?
          # This code expects that the datasets have a just one cluster resource,
          # which is diskspace.
          changes = src.transfer_resources_to_env!(vps_user, dst_node.location.environment)
          changes[changes.keys.first][:row_id] = dst.id
          resources_changes.update(changes)

        else
          ::ClusterResourceUse.for_obj(src).each do |use|
            resources_changes[use] = {row_id: dst.id}
          end
        end

        # Create datasets with canmount=off for the transfer
        append_t(Transactions::Storage::CreateDataset, args: [
          dst,
          {canmount: opts[:rsync] ? 'on' : 'off'},
          {
            set_map: opts[:rsync] ? false : true,
            create_private: opts[:rsync] ? true : false,
          },
        ]) { |t| t.create(dst) }

        # Set all properties except for quotas to ensure send/recv will pass
        props = {}

        src.dataset_properties.where(inherited: false).each do |p|
          next if %w(quota refquota).include?(p.name)
          props[p.name.to_sym] = [p, p.value]
        end

        append(Transactions::Storage::SetDataset, args: [dst, props]) if props.any?
      end

      # Unmount VPS datasets & snapshots in other VPSes
      mounts = Vps::Migrate::MountMigrator.new(self, vps, dst_vps)
      mounts.umount_others

      # Transfer datasets
      migration_snapshots = []

      # Reserve a slot in zfs_send queue
      append(Transactions::Queue::Reserve, args: [src_node, :zfs_send])

      datasets.each do |pair|
        src, dst = pair

        if opts[:rsync]
          append(Transactions::Storage::RsyncDataset, args: [src, dst])

        else
          # Transfer private area. All subdatasets are transfered as well.
          # The two (or three) step transfer is done even if the VPS seems to be stopped.
          # It does not have to be the case, vpsAdmin can have outdated information.
          # First transfer is done when the VPS is running.
          migration_snapshots << use_chain(Dataset::Snapshot, args: src)
          use_chain(Dataset::Transfer, args: [src, dst])
        end
      end

      if @opts[:maintenance_window]
        # Temporarily release the reserved spot in the queue, we'll get another
        # reservation within the maintenance window
        append(Transactions::Queue::Release, args: [src_node, :zfs_send])

        # Wait for the outage window to open
        append(Transactions::MaintenanceWindow::Wait, args: [src_vps, 15])
        append(Transactions::Queue::Reserve, args: [src_node, :zfs_send])
        append(Transactions::MaintenanceWindow::InOrFail, args: [src_vps, 15])

        # Second transfer while inside the outage window. The VPS is still running.
        datasets.each do |pair|
          src, dst = pair

          if opts[:rsync]
            append(Transactions::Storage::RsyncDataset, args: [src, dst], urgent: true)

          else
            migration_snapshots << use_chain(Dataset::Snapshot, args: src, urgent: true)
            use_chain(Dataset::Transfer, args: [src, dst], urgent: true)
          end
        end

        # Check if we're still inside the outage window. We're in if the window
        # closes in not less than 5 minutes. Fail if not.
        append(Transactions::MaintenanceWindow::InOrFail, args: [src_vps, 5], urgent: true)
      end

      # Stop the VPS
      use_chain(Vps::Stop, args: src_vps, urgent: true)

      datasets.each do |pair|
        src, dst = pair

        # The final transfer is done when the VPS is stopped
        if opts[:rsync]
          append(Transactions::Storage::RsyncDataset, args: [src, dst], urgent: true)

        else
          migration_snapshots << use_chain(Dataset::Snapshot, args: src, urgent: true)
          use_chain(Dataset::Transfer, args: [src, dst], urgent: true)
        end
      end

      # Set quotas when all data is transfered
      datasets.each do |pair|
        src, dst = pair
        props = {}

        src.dataset_properties.where(inherited: false, name: %w(quota refquota)).each do |p|
          props[p.name.to_sym] = [p, p.value]
        end

        append(
          Transactions::Storage::SetDataset,
          args: [dst, props],
          urgent: true,
        ) if props.any?
      end

      # Set canmount=noauto on all datasets
      append(
        Transactions::Storage::SetCanmount,
        args: [
          datasets.map { |src, dst| dst },
        ],
        kwargs: {
          canmount: 'noauto',
          mount: opts[:rsync] ? false : true,
        },
        urgent: true,
      )

      # Set uid/gid map when using rsync (otherwise it is set by CreateDataset)
      if opts[:rsync]
        append(
          Transactions::Storage::SetMap,
          args: [datasets.map { |src, dst| [dst, dst.user_namespace_map] }],
          urgent: true,
        )
      end

      # Create empty new VPS
      append(
        Transactions::Vps::Create,
        args: [dst_vps],
        kwargs: {empty: true},
        urgent: true,
      )

      # Configure resources
      append(
        Transactions::Vps::Resources,
        args: [dst_vps, src_vps.get_cluster_resources],
        urgent: true,
      )

      # Transform venet into veth_routed
      src_netif = src_vps.network_interfaces.take!
      dst_netif = ::NetworkInterface.find(src_netif.id)
      dst_netif.vps = dst_vps
      use_chain(
        NetworkInterface.chain_for(dst_netif.kind, :Morph),
        args: [dst_netif, :veth_routed]
      )

      dst_ip_addresses = vps.ip_addresses

      # Migration to different location - remove or replace IP addresses
      migrate_network_interfaces

      # When IPs are unchanged, add them to the new VPS
      if (!location_changed? || @opts[:transfer_ips]) && @opts[:handle_ips]
        vps.ip_addresses.order(:order).each do |ip|
          append(
            Transactions::NetworkInterface::AddRoute,
            args: [dst_netif, ip],
            urgent: true,
          )
        end

        vps.host_ip_addresses.where.not(order: nil).order(:order).each do |addr|
          append(
            Transactions::NetworkInterface::AddHostIp,
            args: [dst_netif, addr],
            urgent: true,
          )
        end
      end

      # Configure DNS resolvers
      if src_vps.dns_resolver
        append(Transactions::Vps::DnsResolver, args: [
          dst_vps,
          src_vps.dns_resolver,
          dst_vps.dns_resolver,
        ])
      end

      # Regenerate mount scripts of the migrated VPS
      mounts.datasets = datasets

      mounts.delete_mine_if do |m|
        # Delete mounts of remote datasets -- those are not supported on vpsAdminOS
        m.dataset_in_pool.pool.node_id != src_node.id
      end

      mounts.remount_mine

      # Wait for routing to remove routes from the original system
      append(Transactions::Vps::WaitForRoutes, args: [dst_vps], urgent: true)

      # Convert internal configuration files to vpsAdminOS based on distribution
      append(Transactions::Vps::VzToOs, args: [dst_vps], urgent: true)

      # Pre-start hook (feature configuration may start the VPS)
      call_hooks_for(:pre_start, self, args: [dst_vps, was_running?])

      # Features
      migrate_features

      # Restore VPS state
      if was_running? && !@opts[:no_start]
        use_chain(
          Vps::Start,
          args: dst_vps,
          urgent: true,
          reversible: @opts[:skip_start] ? :keep_going : nil,
        )
      end

      call_hooks_for(:post_start, self, args: [
        dst_vps,
        was_running? && !@opts[:no_start],
      ])

      # Remount and regenerate mount scripts of mounts in other VPSes
      mounts.remount_others

      # Release reserved spot in the queue
      append(Transactions::Queue::Release, args: [src_node, :zfs_send], urgent: true)

      # Remove migration snapshots
      migration_snapshots.each do |sip|
        dst_sip = sip.snapshot.snapshot_in_pools.joins(:dataset_in_pool).where(
          dataset_in_pools: {pool_id: dst_pool.id}
        ).take!

        use_chain(SnapshotInPool::Destroy, args: dst_sip, urgent: true)
      end

      # Move the dataset in pool to the new pool in the database
      append_t(Transactions::Utils::NoOp, args: dst_node.id, urgent: true) do |t|
        t.edit(src_vps, dataset_in_pool_id: datasets.first[1].id)
        t.edit(src_vps, node_id: dst_node.id)
        t.edit(src_vps, os_template_id: dst_vps.os_template_id)

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

        t.just_create(src_vps.log(:node, {
          src: {id: src_node.id, name: src_node.domain_name},
          dst: {id: dst_node.id, name: dst_node.domain_name},
        }))
      end

      if opts[:rsync]
        # Snapshots have not been transfered, so detach backup heads
        datasets.each do |src, dst|
          use_chain(DatasetInPool::DetachBackupHeads, args: [src])
        end
      end

      # Call DatasetInPool.migrated hook
      datasets.each do |src, dst|
        src.call_hooks_for(:migrated, self, args: [src, dst])
      end

      # Setup firewall and shapers
      # Unregister from firewall and remove shaper on source node
      if @opts[:handle_ips]
        use_chain(Vps::FirewallUnregister, args: src_vps, urgent: true)
        use_chain(Vps::ShaperUnset, args: src_vps, urgent: true)
      end

      # Destroy old dataset in pools
      # Do not detach backup trees and branches
      # Do not delete repeatable tasks - they are re-used for new datasets
      use_chain(DatasetInPool::Destroy, args: [src_vps.dataset_in_pool, {
        recursive: true,
        top: true,
        tasks: false,
        detach_backups: false,
        destroy: @opts[:cleanup_data],
      }])

      # Destroy old root
      append(Transactions::Vps::Destroy, args: src_vps)

      # Mail notification
      notify_finished

      # fail 'ohnoes'
      self
    end
  end
end
