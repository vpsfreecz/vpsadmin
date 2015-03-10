module TransactionChains
  class Vps::Stop < ::TransactionChain
    label 'Stop'

    def link_chain(vps)
      lock(vps)
      set_concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Stop, args: vps)
    end
  end
end
