module TransactionChains
  class NetworkInterface::VethRouted::Morph < ::TransactionChain
    label 'Morph'

    # @param netif [::NetworkInterface]
    # @param target_netif_type [Symbol]
    def link_chain(netif, target_netif_type)
      orig_kind = netif.kind

      ret = send(:"into_#{target_netif_type}", netif)

      ret.call_class_hooks_for(
        :morph,
        self,
        args: [ret, orig_kind, ret.kind],
      )

      ret
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
