module TransactionChains
  class NetworkInterface::AddRoute < ::TransactionChain
    label 'Route+'

    # @param netif [::NetworkInterface]
    # @param ips [Array<::IpAddress>]
    # @param opts [Hash] options
    # @option opts [Boolean] :register (true)
    # @option opts [Boolean] :reallocate (true)
    # @option opts [Array<::HostIpAddress>] :host_addrs
    # @option opts [::HostIpAddress] :via
    def link_chain(netif, ips, opts = {})
      opts[:register] = true unless opts.has_key?(:register)
      opts[:reallocate] = true unless opts.has_key?(:reallocate)
      opts[:host_addrs] ||= []

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
        uses = reallocate_resources(
          netif.vps.user,
          netif.vps.node.location.environment,
          ips_arr,
        )
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
          Transactions::NetworkInterface::AddRoute,
          args: [netif, ip, opts[:register], via: opts[:via]]
        ) do |t|
          route_changes = {
            network_interface_id: netif.id,
            route_via_id: opts[:via] && opts[:via].id,
            order: order[ip.version],
          }

          if ownership && !ip.user_id
            route_changes[:user_id] = netif.vps.user_id
          end

          if opts[:reallocate]
            route_changes[:charged_environment_id] = netif.vps.node.location.environment_id
          end

          t.edit(ip, route_changes)

          t.just_create(
            netif.vps.log(:route_add, {id: ip.id, addr: ip.addr})
          ) unless included?
        end

        order[ip.version] += 1

        host_addrs = opts[:host_addrs].select { |addr| addr.ip_address == ip }
        use_chain(
          NetworkInterface::AddHostIp,
          args: [netif, host_addrs, check_addrs: false]
        ) if host_addrs.any?
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

      use_chain(Export::AddHostsToAll, args: [netif.vps.user, ips_arr])
    end

    protected
    # @return [Array<::ClusterResourceUse>] changes to resource allocations
    def reallocate_resources(user, target_env, ips)
      uses = []
      user_envs = {}

      ips.map do |ip|
        ip.charged_environment_id || target_env.id
      end.each do |env_id|
        user_envs[env_id] ||= user.environment_user_configs.find_by!(
          environment_id: env_id,
        )
      end

      user_envs[target_env.id] ||= user.environment_user_configs.find_by!(
        environment_id: target_env.id,
      )

      %i(ipv4 ipv4_private ipv6).each do |r|
        changes = {}
        user_envs.each_key do |env_id|
          changes[env_id] ||= {add: 0, drop: 0}
        end

        changes[target_env.id] ||= {add: 0, drop: 0}

        recharger = Proc.new do |ip|
          # If the addresses is charged to a different environment, recharge it
          if ip.charged_environment_id && ip.charged_environment_id != target_env.id
            changes[ip.charged_environment_id][:drop] += ip.size
            changes[target_env.id][:add] += ip.size

          # If the address is not yet charged to target_env, charge it
          elsif !target_env.user_ip_ownership || ip.user.nil?
            changes[target_env.id][:add] += ip.size
          end
        end

        case r
        when :ipv4
          ips.select do |ip|
            ip.network.role == 'public_access' && ip.network.ip_version == 4
          end.each(&recharger)

        when :ipv4_private
          ips.select do |ip|
            ip.network.role == 'private_access' && ip.network.ip_version == 4
          end.each(&recharger)

        when :ipv6
          ips.select { |ip| ip.network.ip_version == 6 }.each(&recharger)
        end

        changes.each do |env_id, n|
          user_env = user_envs[env_id]
          cur = user_env.send(r)

          if n[:add] > 0 || n[:drop] > 0
            uses << user_env.reallocate_resource!(
              r,
              cur + n[:add] - n[:drop],
              user: user,
            )
          end
        end
      end

      uses
    end
  end
end
