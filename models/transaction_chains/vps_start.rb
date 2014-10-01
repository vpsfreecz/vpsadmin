module TransactionChains
  class VpsStart < ::TransactionChain
    def link_chain(vps)
      lock(vps)

      append(Transactions::Vps::Start, args: vps)
    end
  end
end
