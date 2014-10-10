module TransactionChains
  class VpsRestart < ::TransactionChain
    label 'Restart VPS'

    def link_chain(vps)
      lock(vps)

      append(Transactions::Vps::Restart, args: vps)
    end
  end
end
