module TransactionChains
  class NetworkInterface::VethRouted::Create < NetworkInterface::Veth::Base
    label 'Veth+'

    # @param vps [::Vps]
    # @param name [String]
    def link_chain(vps, name)
      netif = create_netif(vps, 'veth_routed', name)

      # Create the veth interface
      append_t(
        Transactions::NetworkInterface::CreateVethRouted,
        args: netif
      ) do |t|
        t.just_create(netif)
      end

      netif
    end
  end
end
