module TransactionChains
  class NetworkInterface::Clear < ::TransactionChain
    label 'Netif-'

    # @param netifs [::NetworkInterface, Array<::NetworkInterface>]
    def link_chain(netifs)
      netifs = Array(netifs)
      if netifs.map(&:vps_id).uniq.size > 1
        raise ArgumentError, 'interfaces must belong to one VPS'
      end

      netifs.sort_by(&:id).each do |netif|
        lock(netif.vps)
        lock(netif)
      end

      routes = netifs.flat_map do |netif|
        ips = netif.ip_addresses.joins(:network).where(
          networks: { role: [::Network.roles[:public_access], ::Network.roles[:private_access]] }
        ).to_a
        routed_via, routed_direct = ips.partition(&:route_via_id)
        [[netif, routed_via], [netif, routed_direct]]
      end
      use_chain(NetworkInterface::DelRoute, args: [routes], method: :remove_from_interfaces)
    end
  end
end
