module TransactionChains
  class Vps::Unblock < ::TransactionChain
    label 'Unblock'

    def link_chain(vps, target, state, log)
      use_chain(Vps::Start, args: vps)
    end
  end
end
