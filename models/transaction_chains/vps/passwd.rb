module TransactionChains
  class Vps::Passwd < ::TransactionChain
    label 'Password change'

    def link_chain(vps, passwd)
      lock(vps)

      append(Transactions::Vps::Passwd, args: [vps, passwd])
    end
  end
end
