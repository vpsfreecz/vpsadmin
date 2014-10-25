module TransactionChains
  class Vps::Destroy < ::TransactionChain
    label 'Destroy VPS'

    def link_chain(vps)
      lock(vps.dataset_in_pool)
      lock(vps)

      # Stop VPS
      use_chain(TransactionChains::Vps::Stop, vps)

      # Remove IP addresses
      use_chain(TransactionChains::Vps::DelIp, vps, vps.ip_addresses.all)

      # Remove mounts
      # FIXME: implement mounts removal

      # Destroy VPS
      append(Transactions::Vps::Destroy, args: vps) do
        destroy(vps)
      end

      # Destroy underlying dataset
      # FIXME: what about child datasets?
      append(Transactions::Storage::DestroyDataset, args: vps.dataset_in_pool) do
        destroy(vps.dataset_in_pool)
        destroy(vps.dataset_in_pool.dataset)
      end

      # FIXME: destroy all remaining dataset_in_pools of the VPS dataset
    end
  end
end
