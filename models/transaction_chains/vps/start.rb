module TransactionChains
  class Vps::Start < ::TransactionChain
    label 'Start'

    def link_chain(vps)
      lock(vps)
      set_concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Start, args: vps)
    end
  end
end
