module TransactionChains
  class Vps::DestroyMount < ::TransactionChain
    label 'Destroy'

    def link_chain(mnt, *_args)
      lock(mnt)
      concerns(:affect, [mnt.class.name, mnt.id])

      raise 'snapshot mounts are not supported' if mnt.snapshot_in_pool_id

      use_chain(Vps::UmountDataset, args: [mnt.vps, mnt])
    end
  end
end
