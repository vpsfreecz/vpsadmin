module TransactionChains
  class NetworkInterface::Clear < ::TransactionChain
    label 'Netif-'

    # @param vps [::NetworkInterface]
    def link_chain(netif)
      use_chain(NetworkInterface::DelRoute, args: [
        netif,
        netif.ip_addresses.joins(:network).where(
          networks: {role: [
            ::Network.roles[:public_access],
            ::Network.roles[:private_access],
          ]}
        )
      ])
    end
  end
end
