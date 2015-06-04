module TransactionChains
  class Vps::Revive < ::TransactionChain
    label 'Revive'

    def link_chain(vps, target, state, log)
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      use_chain(TransactionChains::Vps::Start, args: vps)
    end
  end
end
