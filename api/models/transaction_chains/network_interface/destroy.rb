module TransactionChains
  class NetworkInterface::Destroy < ::TransactionChain
    label 'Netif-'

    # @param vps [::NetworkInterface]
    def link_chain(netif, clear: true)
      use_chain(NetworkInterface::Clear, args: netif) if clear

      append_t(Transactions::Utils::NoOp, args: netif.vps.node_id) do |t|
        t.just_destroy(netif)
      end
    end
  end
end
