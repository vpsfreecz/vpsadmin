module TransactionChains
  class Vps::Destroy < ::TransactionChain
    label 'Destroy VPS'

    def link_chain(vps)
      lock(vps.dataset_in_pool)
      lock(vps)

      # Stop VPS
      use_chain(TransactionChains::Vps::Stop, args: vps)

      # Free resources
      resources = vps.free_resources(chain: self)

      # Remove mounts
      # FIXME: implement mounts removal

      # Destroy VPS
      append(Transactions::Vps::Destroy, args: vps) do
        destroy(vps)
        resources.each { |r| destroy(r) }
      end

      # Destroy underlying dataset
      use_chain(DatasetInPool::Destroy, args: [vps.dataset_in_pool, true])
    end
  end
end
