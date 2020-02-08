require_relative 'base'

module TransactionChains
  # Migrate VPS between two OpenVZ nodes
  class Vps::Migrate::OsToOs < Vps::Migrate::Base
    label 'Migrate'

    def link_chain(vps, dst_node, opts = {})
      self.userns_map = vps.userns_map

      setup(vps, dst_node, opts)

      # Mail notification
      notify_begun

      # Transfer resources if the destination node is in a different
      # environment.
      transfer_cluster_resources

      # Prepare userns
      use_chain(UserNamespaceMap::Use, args: [src_vps.userns_map, dst_node])

      # Copy configs
      append(
        Transactions::Vps::SendConfig,
        args: [src_vps, dst_node, network_interfaces: true],
      )

      # Handle dataset resources
      datasets.each do |pair|
        src, dst = pair

        # Transfer resources
        if environment_changed?
          # This code expects that the datasets have just one cluster resource,
          # which is diskspace.
          changes = src.transfer_resources_to_env!(user, dst_node.location.environment)
          changes[changes.keys.first][:row_id] = dst.id
          resources_changes.update(changes)

        else
          ::ClusterResourceUse.for_obj(src).each do |use|
            resources_changes[use] = {row_id: dst.id}
          end
        end
      end

      # Transfer datasets
      unless @opts[:outage_window]
        # Reserve a slot in zfs_send queue
        append(Transactions::Queue::Reserve, args: [src_node, :zfs_send])
      end

      append(Transactions::Vps::SendRootfs, args: [src_vps])

      if @opts[:outage_window]
        # Wait for the outage window to open
        append(Transactions::OutageWindow::Wait, args: [src_vps, 15])
        append(Transactions::Queue::Reserve, args: [src_node, :zfs_send])
        append(Transactions::OutageWindow::InOrFail, args: [src_vps, 15])

        append(Transactions::Vps::SendSync, args: [src_vps], urgent: true)

        # Check if we're still inside the outage window. We're in if the window
        # closes in not less than 5 minutes. Fail if not.
        append(Transactions::OutageWindow::InOrFail, args: [src_vps, 5], urgent: true)
      end

      # Stop the VPS
      use_chain(Vps::Stop, args: src_vps, urgent: true)

      # Send it to the target node
      append(
        Transactions::Vps::SendState,
        args: [src_vps, start: false],
        urgent: true,
      )

      dst_ip_addresses = vps.ip_addresses

      # Migration to different location - remove or replace IP addresses
      migrate_network_interfaces

      # Regenerate mount scripts of the migrated VPS
      mounts = Vps::Migrate::MountMigrator.new(self, vps, dst_vps)
      mounts.datasets = datasets
      mounts.remount_mine

      # Wait for routing to remove routes from the original system
      append(Transactions::Utils::NoOp, args: [find_node_id, sleep: 60], urgent: true)

      # Restore VPS state
      call_hooks_for(:pre_start, self, args: [dst_vps, was_running?])
      use_chain(Vps::Start, args: dst_vps, urgent: true) if was_running?
      call_hooks_for(:post_start, self, args: [dst_vps, was_running?])

      # Release reserved spot in the queue
      append(Transactions::Queue::Release, args: [src_node, :zfs_send], urgent: true)

      # Move the dataset in pool to the new pool in the database
      append_t(Transactions::Utils::NoOp, args: dst_node.id, urgent: true) do |t|
        t.edit(src_vps, dataset_in_pool_id: datasets.first[1].id)
        t.edit(src_vps, node_id: dst_node.id)

        # Transfer resources
        resources_changes.each do |use, changes|
          t.edit(use, changes) unless changes.empty?
        end

        # Transfer datasets and properties
        datasets.each do |src, dst|
          src.dataset_properties.all.each do |p|
            t.edit(p, dataset_in_pool_id: dst.id)
          end

          migrate_dataset_plans(src, dst, t)

          t.destroy(src)
          t.create(dst)
        end

        t.just_create(src_vps.log(:node, {
          src: {id: src_node.id, name: src_node.domain_name},
          dst: {id: dst_node.id, name: dst_node.domain_name},
        }))
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

      # Is is needed to register IP in fw and shaper when changing location,
      # as IPs are removed or replaced sooner.
      unless location_changed?
        # Register to firewall and set shaper on destination node
        use_chain(Vps::FirewallRegister, args: [dst_vps, dst_ip_addresses], urgent: true)
        use_chain(Vps::ShaperSet, args: [dst_vps, dst_ip_addresses], urgent: true)
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
