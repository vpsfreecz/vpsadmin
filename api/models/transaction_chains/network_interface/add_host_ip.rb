module TransactionChains
  class NetworkInterface::AddHostIp < ::TransactionChain
    label 'IP+'

    # @param netif [::NetworkInterface]
    # @param addrs [Array<::HostIpAddress>]
    # @param check_addrs [Boolean]
    def link_chain(netif, addrs, check_addrs: true)
      lock(netif)
      lock(netif.vps)
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      # Ensure all addresses are added to the same interface
      if check_addrs
        addrs.each do |addr|
          next if addr.ip_address.network_interface_id == netif.id

          fail "address #{addr.id} belongs to network routed to interface "+
               "#{addr.ip_address.network_interface_id}, unable to assign to "+
               "interface #{netif.id}"
        end
      end

      # Determine address order
      order = {}

      [4, 6].each do |v|
        last_ip = netif.host_ip_addresses.joins(ip_address: :network).where.not(
          host_ip_addresses: {order: nil},
        ).where(
          networks: {ip_version: v},
        ).order(order: :desc).take

        order[v] = last_ip ? last_ip.order + 1 : 0
      end

      # Add the addresses
      addrs.each do |addr|
        append_t(
          Transactions::NetworkInterface::AddHostIp,
          args: [netif, addr]
        ) do |t|
          t.edit_before(addr, order: nil)
          addr.update!(order: order[addr.version])

          t.just_create(
            netif.vps.log(:host_addr_add, {id: addr.id, addr: addr.ip_addr})
          ) unless included?
        end

        order[addr.version] += 1
      end
    end
  end
end
