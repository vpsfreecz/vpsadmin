module TransactionChains
  class NetworkInterface::VethRouted::Clone < NetworkInterface::Veth::Base
    label 'Clone'

    # @param src_netif [::NetworkInterface]
    # @param dst_vps [::Vps]
    def link_chain(src_netif, dst_vps)
      netif = clone_netif(src_netif, dst_vps)

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
