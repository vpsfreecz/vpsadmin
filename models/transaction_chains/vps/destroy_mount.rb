module TransactionChains
  class Vps::DestroyMount < ::TransactionChain
    label 'Destroy'

    def link_chain(mnt, *args)
      lock(mnt)
      concerns(:affect, [mnt.class.name, mnt.id])
      
      if mnt.snapshot_in_pool
        use_chain(Vps::UmountSnapshot, args: [mnt.vps, mnt])

      else
        use_chain(Vps::UmountDataset, args: [mnt.vps, mnt])
      end
    end
  end
end
