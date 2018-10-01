module TransactionChains
  class NetworkInterface::AddHostIp < ::TransactionChain
    label 'IP+'

    # @param netif [::NetworkInterface]
    # @param addrs [Array<::HostIpAddress>]
    def link_chain(netif, addrs)
      lock(netif)
      lock(netif.vps)
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      # Ensure all addresses are added to the same interface
      addrs.each do |addr|
        next if addr.ip_address.network_interface_id == netif.id

        fail "address #{addr} belongs to network routed to interface "+
             "#{addr.ip_address.network_interface}, unable to assign to "+
             "interface #{netif}"
      end

      # Determine address order
      order = {}

      [4, 6].each do |v|
        last_ip = netif.host_ip_addresses.joins(ip_address: :network).where.not(
          host_ip_addresses: {order: nil},
        ).where(
          networks: {ip_version: v},
        ).order('`order` DESC').take

        order[v] = last_ip ? last_ip.order + 1 : 0
      end

      # Add the addresses
      addrs.each do |addr|
        append_t(Transactions::NetworkInterface::AddHostIp, args: addr) do |t|
          t.edit(addr, order: order[addr.version])

          t.just_create(
            netif.vps.log(:host_addr_add, {id: addr.id, addr: addr.ip_addr})
          ) unless included?
        end

        order[addr.version] += 1
      end
    end
  end
end
