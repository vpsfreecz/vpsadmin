require_relative 'base'
require 'securerandom'

module TransactionChains
  # Migrate VPS between two OpenVZ nodes
  class Vps::Migrate::OsToOs < Vps::Migrate::Base
    label 'Migrate'

    def link_chain(vps, dst_node, opts = {})
      self.userns_map = vps.user_namespace_map

      setup(vps, dst_node, opts)
      token = SecureRandom.hex(6)

      # Check swap is available on the destination node
      check_swap!

      # Check the target node is compatible with the VPS
      check_cgroup_version!

      # Mail notification
      notify_begun

      # Transfer resources if the destination node is in a different
      # environment.
      transfer_cluster_resources

      # Prepare userns
      use_chain(UserNamespaceMap::Use, args: [dst_vps, src_vps.user_namespace_map])

      # Authorize the migration
      append(
        Transactions::Pool::AuthorizeSendKey,
        args: [dst_pool, src_pool, vps.id, "chain-#{id}-#{token}", token]
      )

      # Copy configs
      append(
        Transactions::Vps::SendConfig,
        args: [
          src_vps,
          dst_node,
          dst_pool
        ],
        kwargs: {
          network_interfaces: true,
          passphrase: token
        }
      )

      # In case of rollback on the target node
      append(Transactions::Vps::SendRollbackConfig, args: dst_vps)

      # Handle dataset resources
      datasets.each do |pair|
        src, dst = pair

        # Transfer resources
        if environment_changed?
          # This code expects that the datasets have just one cluster resource,
          # which is diskspace.
          changes = src.transfer_resources_to_env!(vps_user, dst_node.location.environment)
          changes[changes.keys.first][:row_id] = dst.id
          resources_changes.update(changes)

        else
          ::ClusterResourceUse.for_obj(src).each do |use|
            resources_changes[use] = { row_id: dst.id }
          end
        end
      end

      # Reserve a slot in zfs_recv and zfs_send queues
      append(Transactions::Queue::Reserve, args: [src_node, :zfs_send])
      append(Transactions::Queue::Reserve, args: [dst_node, :zfs_recv])

      # Initial transfer
      append(Transactions::Vps::SendRootfs, args: [src_vps])

      if use_maintenance_window?
        # Temporarily release the reserved spot in the queue, we'll get another
        # reservation within the maintenance window
        append(Transactions::Queue::Release, args: [dst_node, :zfs_recv])
        append(Transactions::Queue::Release, args: [src_node, :zfs_send])

        # Wait for the outage window to open
        append(
          Transactions::MaintenanceWindow::Wait,
          args: [src_vps, 15],
          kwargs: { maintenance_windows: }
        )
        append(Transactions::Queue::Reserve, args: [src_node, :zfs_send])
        append(Transactions::Queue::Reserve, args: [dst_node, :zfs_recv])
        append(
          Transactions::MaintenanceWindow::InOrFail,
          args: [src_vps, 15],
          kwargs: { maintenance_windows: }
        )

        append(Transactions::Vps::SendSync, args: [src_vps], urgent: true)

        # Check if we're still inside the outage window. We're in if the window
        # closes in not less than 5 minutes. Fail if not.
        append(
          Transactions::MaintenanceWindow::InOrFail,
          args: [src_vps, 5],
          kwargs: { maintenance_windows: },
          urgent: true
        )
      end

      # Stop the VPS
      use_chain(
        Vps::Stop,
        args: src_vps,
        kwargs: { start_timeout:, rollback_stop: was_running? },
        urgent: true
      )

      # Wait for routing to remove routes from the target system during rollback
      append(
        Transactions::Vps::WaitForRoutes,
        args: [src_vps],
        kwargs: { direction: :rollback },
        urgent: true
      )

      # Send it to the target node
      append(
        Transactions::Vps::SendState,
        args: [src_vps],
        kwargs: { start: false },
        urgent: true
      )

      dst_ip_addresses = vps.ip_addresses

      # Migration to different location - remove or replace IP addresses
      migrate_network_interfaces

      # Regenerate mount scripts of the migrated VPS
      mounts = Vps::Migrate::MountMigrator.new(self, vps, dst_vps)
      mounts.datasets = datasets
      mounts.remount_mine

      # Wait for routing to remove routes from the original system
      append(Transactions::Vps::WaitForRoutes, args: [dst_vps], urgent: true)

      # Restore VPS state
      call_hooks_for(:pre_start, self, kwargs: { chain: self, dst_vps:, running: was_running? })

      if was_running? && !@opts[:no_start]
        use_chain(
          Vps::Start,
          args: dst_vps,
          kwargs: { start_timeout: },
          urgent: true,
          reversible: @opts[:skip_start] ? :keep_going : nil
        )
      end

      call_hooks_for(:post_start, self, kwargs: {
                       chain: self,
                       dst_vps:,
                       running: was_running? && !@opts[:no_start]
                    })

      # Release reserved spot in the queue
      append(Transactions::Queue::Release, args: [dst_node, :zfs_recv], urgent: true)
      append(Transactions::Queue::Release, args: [src_node, :zfs_send], urgent: true)

      # Move the dataset in pool to the new pool in the database
      append_t(Transactions::Utils::NoOp, args: dst_node.id, urgent: true) do |t|
        t.edit(src_vps, dataset_in_pool_id: datasets.first[1].id)
        t.edit(src_vps, node_id: dst_node.id)

        # Transfer resources
        resources_changes.each do |use, changes|
          t.edit(use, changes) unless changes.empty?
        end

        # Transfer datasets, snapshots and properties
        datasets.each do |src, dst|
          src.dataset_properties.all.each do |p|
            t.edit(p, dataset_in_pool_id: dst.id)
          end

          src.snapshot_in_pools.each do |sip|
            t.edit(sip, dataset_in_pool_id: dst.id)
          end

          migrate_dataset_plans(src, dst, t)

          t.destroy(src)
          t.create(dst)
        end

        t.just_create(src_vps.log(:node, {
                                    src: { id: src_node.id, name: src_node.domain_name },
                                    dst: { id: dst_node.id, name: dst_node.domain_name }
                                  }))
      end

      # Call DatasetInPool.migrated hook
      datasets.each do |src, dst|
        src.call_hooks_for(:migrated, self, args: [src, dst])
      end

      # Destroy old VPS
      append(Transactions::Vps::SendCleanup, args: src_vps)
      append(Transactions::Vps::RemoveConfig, args: src_vps)

      # Free userns map
      use_chain(UserNamespaceMap::Disuse, args: [src_vps])

      # Mail notification
      notify_finished

      # fail 'ohnoes'
      self
    end
  end
end
