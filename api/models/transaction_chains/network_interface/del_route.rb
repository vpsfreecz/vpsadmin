module TransactionChains
  class NetworkInterface::DelRoute < ::TransactionChain
    label 'Route-'

    # @param netif [::NetworkInterface]
    # @param ips [Array<::IpAddress>]
    # @param opts [Hash] options
    # @option opts [Boolean] :unregister
    # @option opts [Boolean] :reallocate
    # @option opts [Boolean] :phony
    # @option opts [Environment] :environment
    def link_chain(netif, ips, **opts)
      lock(netif)
      lock(netif.vps)
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      opts[:unregister] = true unless opts.has_key?(:unregister)
      opts[:reallocate] = true unless opts.has_key?(:reallocate)

      lock(netif.vps)
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      env = opts[:environment] || netif.vps.node.location.environment

      uses = []
      user_env = netif.vps.user.environment_user_configs.find_by!(
        environment: env,
      )
      ips_arr = ips.to_a

      if opts[:reallocate] && !env.user_ip_ownership
        %i(ipv4 ipv4_private ipv6).each do |r|
          cnt = case r
          when :ipv4
            ips_arr.inject(0) do |sum, ip|
              if ip.network.role == 'public_access' && ip.network.ip_version == 4
                sum + ip.size

              else
                sum
              end
            end

          when :ipv4_private
            ips_arr.inject(0) do |sum, ip|
              if ip.network.role == 'private_access' && ip.network.ip_version == 4
                sum + ip.size

              else
                sum
              end
            end

          when :ipv6
            ips_arr.inject(0) do |sum, ip|
              if ip.network.ip_version == 6
                sum + ip.size

              else
                sum
              end
            end
          end

          uses << user_env.reallocate_resource!(
            r,
            user_env.send(r) - cnt,
            user: netif.vps.user
          )
        end
      end

      ips_arr.each do |ip|
        lock(ip)

        use_chain(
          NetworkInterface::DelHostIp,
          args: [
            netif,
            ip.host_ip_addresses.where.not(order: nil).to_a,
          ],
          kwargs: {phony: opts[:phony]},
        )

        if opts[:phony]
          append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
            ip_confirmation(t, netif, ip, env)
          end
        else
          append_t(
            Transactions::NetworkInterface::DelRoute,
            args: [netif, ip, opts[:unregister]]
          ) { |t| ip_confirmation(t, netif, ip, env) }
        end
      end

      append_t(Transactions::Utils::NoOp, args: netif.vps.node_id) do |t|
        uses.each do |use|
          if use.updating?
            t.edit(use, value: use.value)
          else
            t.create(use)
          end
        end
      end unless uses.empty?

      use_chain(Export::DelHostsFromAll, args: [netif.vps.user, ips_arr])
    end

    protected
    def ip_confirmation(t, netif, ip, env)
      changes = {
        network_interface_id: nil,
        route_via_id: nil,
        order: nil,
      }

      if !env.user_ip_ownership
        changes[:charged_environment_id] = nil

        ip.host_ip_addresses.where(user_created: true).each do |host|
          t.just_destroy(host)
        end
      end

      t.edit(ip, changes)

      t.just_create(
        netif.vps.log(:route_del, {id: ip.id, addr: ip.addr})
      ) unless included?

      ip.log_unassignment(chain: current_chain, confirmable: t)
    end
  end
end
