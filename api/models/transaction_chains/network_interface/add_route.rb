module TransactionChains
  class NetworkInterface::AddRoute < ::TransactionChain
    label 'Route+'

    # @param netif [::NetworkInterface]
    # @param ips [Array<::IpAddress>]
    # @param opts [Hash] options
    # @option opts [Boolean] :register (true)
    # @option opts [Boolean] :reallocate (true)
    def link_chain(netif, ips, opts = {})
      opts[:register] = true unless opts.has_key?(:register)
      opts[:reallocate] = true unless opts.has_key?(:reallocate)

      lock(netif)
      lock(netif.vps)
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      if netif.vps.node.openvz? && ips.detect { |ip| ip.size > 1 }
        raise VpsAdmin::API::Exceptions::NotAvailableOnOpenVz,
              "cannot add IP address with prefix other than /32 or /128"
      end

      uses = []
      user_env = netif.vps.user.environment_user_configs.find_by!(
        environment: netif.vps.node.location.environment,
      )
      ownership = netif.vps.node.location.environment.user_ip_ownership
      ips_arr = ips.to_a

      if opts[:reallocate]
        %i(ipv4 ipv4_private ipv6).each do |r|
          cnt = case r
          when :ipv4
            ips_arr.inject(0) do |sum, ip|
              if (!ownership || ip.user.nil?) \
                 && ip.network.role == 'public_access' && ip.network.ip_version == 4
                sum + ip.size

              else
                sum
              end
            end

          when :ipv4_private
            ips_arr.inject(0) do |sum, ip|
              if (!ownership || ip.user.nil?) \
                 && ip.network.role == 'private_access' && ip.network.ip_version == 4
                sum + ip.size

              else
                sum
              end
            end

          when :ipv6
            ips_arr.inject(0) do |sum, ip|
              if (!ownership || ip.user.nil?) && ip.network.ip_version == 6
                sum + ip.size

              else
                sum
              end
            end
          end

          cur = user_env.send(r)

          uses << user_env.reallocate_resource!(
            r,
            cur + cnt,
            user: netif.vps.user
          ) if cnt != 0
        end
      end

      order = {}
      [4, 6].each do |v|
        last_ip = netif.ip_addresses.joins(:network).where(
          networks: {ip_version: v}
        ).order('`order` DESC').take

        order[v] = last_ip ? last_ip.order + 1 : 0
      end

      ips_arr.each do |ip|
        lock(ip)

        append_t(
          Transactions::NetworkInterface::RouteAdd,
          args: [netif, ip, opts[:register]]
        ) do |t|
          t.edit(ip, network_interface_id: netif.id, order: order[ip.version])
          t.edit(ip, user_id: netif.vps.user_id) if ownership && !ip.user_id

          t.just_create(
            netif.vps.log(:route_add, {id: ip.id, addr: ip.addr})
          ) unless included?
        end

        order[ip.version] += 1
      end

      append(Transactions::Utils::NoOp, args: netif.vps.node_id) do
        uses.each do |use|
          if use.updating?
            edit(use, value: use.value)
          else
            create(use)
          end
        end
      end unless uses.empty?
    end
  end
end
