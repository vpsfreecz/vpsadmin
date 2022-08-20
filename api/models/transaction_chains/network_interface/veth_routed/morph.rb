module TransactionChains
  class NetworkInterface::VethRouted::Morph < ::TransactionChain
    label 'Morph'

    # @param netif [::NetworkInterface]
    # @param target_netif_type [Symbol]
    def link_chain(netif, target_netif_type)
      send(:"into_#{target_netif_type}", netif)
    end

    protected
    def into_venet(netif)
      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.edit(
          netif,
          kind: ::NetworkInterface.kinds[:venet],
          mac: nil,
        )
      end

      netif
    end
  end
end
