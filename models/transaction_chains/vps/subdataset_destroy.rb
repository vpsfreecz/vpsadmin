module TransactionChains
  class Vps::SubdatasetDestroy < ::TransactionChain
    label 'VPS subdataset-'

    def link_chain(vps, dataset_in_pool)
      use_chain(Vps::Umount, args: [vps, dataset_in_pool])
      use_chain(DatasetInPool::Destroy, args: [dataset_in_pool, true])

      # Mounts must be called after DatasetInPool::Destroy, since the destroy
      # marks the datasets as "to be destroyed" and mounts then don't
      # include them.
      use_chain(Vps::Mounts, args: vps)
    end
  end
end
