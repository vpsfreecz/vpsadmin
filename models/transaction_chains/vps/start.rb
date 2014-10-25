module TransactionChains
  class Vps::Start < ::TransactionChain
    label 'Start VPS'

    def link_chain(vps)
      lock(vps)

      append(Transactions::Vps::Start, args: vps)
    end
  end
end
