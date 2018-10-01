module TransactionChains
  class NetworkInterface::DelHostIp < ::TransactionChain
    label 'IP-'

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
             "#{addr.ip_address.network_interface}, unable to remove from "+
             "interface #{netif}"
      end

      # Add the addresses
      addrs.each do |addr|
        append_t(Transactions::NetworkInterface::DelHostIp, args: [netif, addr]) do |t|
          t.edit(addr, order: nil)

          t.just_create(
            netif.vps.log(:host_addr_del, {id: addr.id, addr: addr.ip_addr})
          ) unless included?
        end
      end
    end
  end
end
