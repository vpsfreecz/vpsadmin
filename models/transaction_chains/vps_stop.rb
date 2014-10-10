module TransactionChains
  class VpsStop < ::TransactionChain
    label 'Stop VPS'

    def link_chain(vps)
      lock(vps)

      append(Transactions::Vps::Stop, args: vps)
    end
  end
end
