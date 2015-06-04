module TransactionChains
  class Vps::Block < ::TransactionChain
    label 'Block'

    def link_chain(vps, target, state, log)
      use_chain(Vps::Stop, args: vps)
    end
  end
end
