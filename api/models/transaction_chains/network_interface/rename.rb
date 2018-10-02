module TransactionChains
  class NetworkInterface::Rename < ::TransactionChain
    label 'Modify'

    def link_chain(netif, new_name)
      lock(netif)
      lock(netif.vps)
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      append_t(Transactions::NetworkInterface::Rename, args: [
        netif,
        netif.name,
        new_name,
      ]) do |t|
        t.edit(netif, name: new_name)
      end
    end
  end
end
