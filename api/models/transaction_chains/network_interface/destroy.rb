module TransactionChains
  class NetworkInterface::Destroy < ::TransactionChain
    label 'Netif-'

    # @param vps [::NetworkInterface]
    def link_chain(netif, clear: true)
      use_chain(NetworkInterface::Clear, args: netif) if clear

      if netif.veth_routed?
        append_t(Transactions::Vps::RemoveVeth, args: netif) do |t|
          t.just_destroy(netif)
        end
      else
        append_t(Transactions::Utils::NoOp, args: netif.vps.node_id) do |t|
          t.just_destroy(netif)
        end
      end
    end
  end
end
