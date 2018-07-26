module TransactionChains
  class NetworkInterface::Venet::Create < ::TransactionChain
    label 'Venet+'

    # @param vps [::Vps]
    def link_chain(vps)
      netif = ::NetworkInterface.create!(
        vps: vps,
        kind: 'venet',
        name: 'venet0',
      )

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_create(netif)
      end

      netif
    end
  end
end
