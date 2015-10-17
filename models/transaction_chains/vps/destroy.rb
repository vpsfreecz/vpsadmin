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
      # FIXME: implement mounts removal

      # Destroy VPS
      append(Transactions::Vps::Destroy, args: vps) do
        resources.each { |r| destroy(r) }
      end

      # Destroy underlying dataset
      use_chain(DatasetInPool::Destroy, args: [vps.dataset_in_pool, true])

      # The dataset_in_pool_id must be unset after the dataset is actually
      # deleted, as it may fail.
      append(Transactions::Utils::NoOp, args: find_node_id) do
        edit(vps, dataset_in_pool_id: nil)
      end
    end
  end
end
