module TransactionChains
  class Vps::StopOverQuota < ::TransactionChain
    label 'StopQuota'

    def link_chain(vps, dataset_expansion)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      use_chain(Vps::Stop, args: [vps])
    end
  end
end
