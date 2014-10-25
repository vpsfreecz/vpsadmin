module TransactionChains
  class Vps::Stop < ::TransactionChain
    label 'Stop VPS'

    def link_chain(vps)
      lock(vps)

      append(Transactions::Vps::Stop, args: vps)
    end
  end
end
