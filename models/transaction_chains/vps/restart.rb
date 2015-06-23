module TransactionChains
  class Vps::Restart < ::TransactionChain
    label 'Restart'

    def link_chain(vps)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Restart, args: vps)
    end
  end
end
