module TransactionChains
  class Vps::Destroy < ::TransactionChain
    label 'Destroy'

    def link_chain(vps, _target, _state, _log)
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      # Stop VPS - should definitely be already stopped
      use_chain(TransactionChains::Vps::Stop, args: vps, kwargs: { rollback_stop: false })

      # Free resources
      resources = vps.free_resources(chain: self)

      # Remove mounts
      vps.mounts.each do |mnt|
        raise 'snapshot mounts are not supported' if mnt.snapshot_in_pool_id

        use_chain(Vps::UmountDataset, args: [vps, mnt, false])
      end

      use_chain(Vps::Mounts, args: vps) if vps.mounts.any?

      # Remove network interfaces
      vps.network_interfaces.each do |netif|
        use_chain(NetworkInterface::Destroy, args: netif)
      end

      # Destroy the underlying dataset, but only in database
      #
      # On vpsAdminOS, all container's datasets are deleted by
      # `Transactions::Vps::Destroy` as part of `osctl ct del`. That's why
      # the datasets need to be actually destroyed only on OpenVZ nodes.
      #
      # Because the datasets may have subdatasets that are mounted to
      # the VPS that is being destroyed, we need to handle them before
      # the container is deleted by osctld. It may issue mounts/umount
      # transactions and osctl expects the container to exist when
      # evaluating them.
      use_chain(
        DatasetInPool::Destroy,
        args: [vps.dataset_in_pool, { recursive: true, destroy: false }]
      )

      # Destroy VPS
      append(Transactions::Vps::Destroy, args: vps) do
        resources.each { |r| destroy(r) }
        just_destroy(vps.vps_current_status) if vps.vps_current_status
      end

      use_chain(UserNamespaceMap::Disuse, args: [vps])

      # The dataset_in_pool_id must be unset after the dataset is actually
      # deleted, as it may fail.
      append(Transactions::Utils::NoOp, args: find_node_id) do
        edit(vps, dataset_in_pool_id: nil, user_namespace_map_id: nil)
      end

      # Delete OOM Reports
      vps.oom_reports.delete_all
      vps.oom_report_counters.delete_all

      # Delete OS process counts
      vps.vps_os_processes.delete_all

      # Delete SSH host keys
      vps.vps_ssh_host_keys.delete_all

      # NOTE: there are too many records to delete them using transaction confirmations.
      # All VPS statuses are deleted whether the chain is successful or not.
      vps.vps_statuses.delete_all
    end
  end
end
