module TransactionChains
  class NetworkInterface::Clear < ::TransactionChain
    label 'Netif-'

    # @param vps [::NetworkInterface]
    def link_chain(netif)
      routed_via = []
      routed_direct = []

      netif.ip_addresses.joins(:network).where(
        networks: {role: [
          ::Network.roles[:public_access],
          ::Network.roles[:private_access],
        ]},
      ).each do |ip|
        if ip.route_via_id
          routed_via << ip
        else
          routed_direct << ip
        end
      end

      use_chain(NetworkInterface::DelRoute, args: [netif, routed_via])
      use_chain(NetworkInterface::DelRoute, args: [netif, routed_direct])
    end
  end
end
