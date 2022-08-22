module TransactionChains
  class NetworkInterface::Venet::Clone < ::TransactionChain
    label 'Clone'

    # @param src_netif [::NetworkInterface]
    # @param dst_vps [::Vps]
    def link_chain(src_netif, dst_vps)
      new_netif = ::NetworkInterface.create!(
        vps: dst_vps,
        kind: src_netif.kind,
        name: src_netif.name,
        mac: nil,
      )

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_create(new_netif)
      end

      src_netif.call_class_hooks_for(
        :clone,
        self,
        args: [src_netif, new_netif],
      )

      new_netif
    end
  end
end
