module TransactionChains
  class VpsRestart < ::TransactionChain
    def link_chain(vps)
      lock(vps)

      append(Transactions::Vps::Restart, args: vps)
    end
  end
end
