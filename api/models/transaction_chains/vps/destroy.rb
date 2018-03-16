module TransactionChains
  class Vps::Destroy < ::TransactionChain
    label 'Destroy'

    def link_chain(vps, target, state, log)
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      # Stop VPS - should definitely be already stopped
      use_chain(TransactionChains::Vps::Stop, args: vps)

      # Free resources
      resources = vps.free_resources(chain: self)

      # Remove mounts
      vps.mounts.each do |mnt|
        if mnt.snapshot_in_pool_id
          use_chain(Vps::UmountSnapshot, args: [vps, mnt, false])

        else
          use_chain(Vps::UmountDataset, args: [vps, mnt, false])
        end
      end

      use_chain(Vps::Mounts, args: vps) if vps.mounts.any?

      # Destroy VPS
      append(Transactions::Vps::Destroy, args: vps) do
        resources.each { |r| destroy(r) }
        just_destroy(vps.vps_current_status) if vps.vps_current_status
      end

      # Destroy the underlying dataset
      #
      # On vpsAdminOS, all container's datasets are deleted by
      # `Transactions::Vps::Destroy` as part of `osctl ct del`. That's why
      # the datasets need to be actually destroyed only on OpenVZ nodes.
      use_chain(
          DatasetInPool::Destroy,
          args: [vps.dataset_in_pool, {recursive: true, destroy: vps.node.openvz?}]
      )

      # The dataset_in_pool_id must be unset after the dataset is actually
      # deleted, as it may fail.
      append(Transactions::Utils::NoOp, args: find_node_id) do
        edit(vps, dataset_in_pool_id: nil)
      end

      # TODO: check if the namespace isn't used by other datasets
      use_chain(UserNamespace::Free, args: [vps.dataset_in_pool.user_namespace, vps.node])

      # Note: there are too many records to delete them using transaction confirmations.
      # All VPS statuses are deleted whether the chain is successful or not.
      vps.vps_statuses.delete_all
    end
  end
end
