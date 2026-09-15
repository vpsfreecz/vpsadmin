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
      netif.ensure_actor!(opts[:actor]) if opts[:actor]
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      opts[:unregister] = true unless opts.has_key?(:unregister)
      opts[:reallocate] = true unless opts.has_key?(:reallocate)

      ips_arr = ips.to_a
      ::IpAddress.lock_all_current!(self, ips_arr)
      ips_arr.each do |ip|
        ip.ensure_charge_environment!
        ip.ensure_owner!(opts[:actor]) if opts[:actor]
        unless ip.network_interface_id == netif.id && (!ip.user_id || ip.user_id == netif.vps.user_id)
          raise VpsAdmin::API::Exceptions::IpAddressNotAssigned, 'IP address is no longer assigned to this interface'
        end

        netif.validate_route_removal!(ip) if opts[:actor]
      end

      env = opts[:environment] || netif.vps.node.location.environment

      changes = Hash.new(0)
      record_resource_changes(changes, netif, ips_arr, env) if opts[:reallocate]
      uses = apply_resource_changes(changes)

      ips_arr.each do |ip|
        use_chain(
          NetworkInterface::DelHostIp,
          args: [
            netif,
            ip.host_ip_addresses.where.not(order: nil).to_a
          ],
          kwargs: { phony: opts[:phony] }
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

      confirm_resource_changes(uses, netif.vps.node_id)

      ips_arr.each do |ip|
        ip.host_ip_addresses.order(:id).lock.each do |host_ip|
          host_ip.lock_with_ip!(self)
          host_ip.remove_dns_transfers!(self)
        end
      end

      use_chain(NetworkInterface::CleanupHostIpAddresses, kwargs: {
        ips: ips_arr,
        delete: !env.user_ip_ownership
      })

      use_chain(Export::DelHostsFromAll, args: [netif.vps.user, ips_arr])
    end

    # Clear groups/interfaces together so deferred totals cannot overwrite
    # deductions staged by an earlier included DelRoute chain.
    def remove_from_interfaces(routes)
      ::IpAddress.lock_all_current!(self, routes.flat_map { |_netif, ips| ips })
      changes = Hash.new(0)
      routes.each do |netif, ips|
        next if ips.empty?

        use_chain(self.class, args: [netif, ips], kwargs: { reallocate: false })
        record_resource_changes(changes, netif, ips, netif.vps.node.location.environment)
      end
      return if changes.empty?

      confirm_resource_changes(apply_resource_changes(changes), routes.first.first.vps.node_id)
    end

    protected

    def record_resource_changes(changes, netif, ips, env)
      return if env.user_ip_ownership || ips.empty?

      config = netif.vps.user.environment_user_configs.find_by!(environment: env)
      ips.each do |ip|
        resource = if ip.version == 6
                     :ipv6
                   elsif ip.network.role == 'public_access'
                     :ipv4
                   elsif ip.network.role == 'private_access'
                     :ipv4_private
                   end
        changes[[config, resource]] -= ip.size if resource
      end
    end

    def apply_resource_changes(changes)
      changes.keys.map(&:first).uniq(&:id).sort_by(&:id).each(&:lock!)
      changes.map do |(config, resource), delta|
        config.adjust_resource!(resource, delta:, user: config.user, chain: self)
      end
    end

    def confirm_resource_changes(uses, node_id)
      return if uses.empty?

      append_t(Transactions::Utils::NoOp, args: node_id) do |t|
        uses.each do |use|
          if use.updating?
            t.edit(use, value: use.value)
          else
            t.create(use)
          end
        end
      end
    end

    def ip_confirmation(t, netif, ip, env)
      changes = {
        network_interface_id: nil,
        route_via_id: nil,
        order: nil
      }

      unless env.user_ip_ownership
        changes[:charged_environment_id] = nil
      end

      t.edit(ip, changes)

      unless included?
        t.just_create(
          netif.vps.log(:route_del, { id: ip.id, addr: ip.addr })
        )
      end

      ip.log_unassignment(chain: current_chain, confirmable: t)
    end
  end
end
