module TransactionChains
  class NetworkInterface::DelHostIp < ::TransactionChain
    label 'IP-'

    # @param netif [::NetworkInterface]
    # @param addrs [Array<::HostIpAddress>]
    # @param opts [Hash]
    # @option opts [Boolean] :phony
    def link_chain(netif, addrs, **opts)
      lock(netif)
      lock(netif.vps)
      netif.ensure_actor!(opts[:actor]) if opts[:actor]
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      addrs.sort_by { |addr| [addr.ip_address_id, addr.id] }.each do |addr|
        addr.lock_with_ip!(self, actor: opts[:actor])
        next unless opts[:actor]
        raise VpsAdmin::API::Exceptions::IpAddressNotAssigned unless addr.assigned?
        if addr.routed_via_addresses.lock.exists?
          raise VpsAdmin::API::Exceptions::IpAddressInUse, 'One or more networks are routed via this address'
        end
      end

      # Ensure all addresses are added to the same interface
      addrs.each do |addr|
        next if addr.ip_address.network_interface_id == netif.id

        raise "address #{addr} belongs to network routed to interface " \
              "#{addr.ip_address.network_interface}, unable to remove from " \
              "interface #{netif}"
      end

      # Delete the addresses
      if opts[:phony]
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          addrs.each { |addr| addr_confirmation(t, netif, addr) }
        end

      else
        addrs.each do |addr|
          append_t(Transactions::NetworkInterface::DelHostIp, args: [netif, addr]) do |t|
            addr_confirmation(t, netif, addr)
          end
        end
      end
    end

    protected

    def addr_confirmation(t, netif, addr)
      t.edit(addr, order: nil)

      return if included?

      t.just_create(
        netif.vps.log(:host_addr_del, { id: addr.id, addr: addr.ip_addr })
      )
    end
  end
end
