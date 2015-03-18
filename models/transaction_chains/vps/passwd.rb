module TransactionChains
  class Vps::Passwd < ::TransactionChain
    label 'Password'

    def link_chain(vps, passwd)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Passwd, args: [vps, passwd])
    end
  end
end
