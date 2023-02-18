module TransactionChains
  # Swap two VPSes between different locations, be it within the same
  # environment or two different environments.
  #
  # It is not possible to swap VPSes within the same location, as it makes
  # no sense, it is sufficient to swap just IP addresses in that case.
  #
  # The two VPSes are migrated between their nodes and their IP addresses
  # are swapped. The VPSes have two roles - primary and secondary. Primary
  # is the one on which you call the swap action and the secondary one is
  # the one you supply as a parameter. During the swap, they switch the roles.
  # The primary VPS is considered more important and it's downtime it's kept to
  # minimum, where as the secondary VPS is down longer.
  class Vps::Swap < ::TransactionChain
    label 'Swap'

    def link_chain(primary_vps, secondary_vps, opts)
      lock(primary_vps)
      lock(secondary_vps)
      concerns(:transform,
        [secondary_vps.class.name, secondary_vps.id],
        [primary_vps.class.name, primary_vps.id]
      )

      # Migrate secondary VPS to primary node
      # Stop primary VPS, switch IP addresses
      # Switch secondary and primary VPS
      # Start new primary VPS
      # Move old primary to secondary node
      # Add IP addresses, start new secondary VPS

      new_primary_vps = ::Vps.find(secondary_vps.id)
      new_primary_vps.node = primary_vps.node

      new_secondary_vps = ::Vps.find(primary_vps.id)
      new_secondary_vps.node = secondary_vps.node

      same_env = primary_vps.node.location.environment_id \
                 == secondary_vps.node.location.environment_id
      faked_resources = []

      # Free resources, just mark them as for destroyal so that the VPSes
      # can be migrated without any extra resources available.
      # Necessary for the migration to pass ClusterResourceUse#valid?.
      faked_resources.concat(primary_vps.free_resources(chain: self,
                                                        free_objects: false))
      faked_resources.concat(secondary_vps.free_resources(chain: self,
                                                          free_objects: false))

      primary_vps.dataset_in_pool.dataset.subtree.arrange.each do |k, v|
        faked_resources.concat(
          recursive_serialize(k, v, primary_vps.dataset_in_pool.pool)
        )
      end

      secondary_vps.dataset_in_pool.dataset.subtree.arrange.each do |k, v|
        faked_resources.concat(
          recursive_serialize(k, v, secondary_vps.dataset_in_pool.pool)
        )
      end

      # Save IP addresses for later
      #
      # In the future, we will distinguish public and private interfaces. Now
      # we assume that there's only one public interface.
      primary_netifs = Hash[primary_vps.network_interfaces.map do |netif|
        new_netif = ::NetworkInterface.find(netif.id)
        new_netif.vps.node = secondary_vps.node

        [
          :public,
          netif: netif,
          target_netif: new_netif,
          routes: netif.ip_addresses.order(:order).to_a,
          host_addrs: netif.host_ip_addresses.where.not(order: nil).order(:order).to_a,
        ]
      end]

      secondary_netifs = Hash[secondary_vps.network_interfaces.map do |netif|
        new_netif = ::NetworkInterface.find(netif.id)
        new_netif.vps.node = primary_vps.node

        [
          :public,
          netif: netif,
          target_netif: new_netif,
          routes: netif.ip_addresses.order(:order).to_a,
          host_addrs: netif.host_ip_addresses.where.not(order: nil).order(:order).to_a,
        ]
      end]

      # Check that interfaces match
      %i(public private).each do |netif_type|
        if primary_netifs[netif_type].nil? != secondary_netifs[netif_type].nil?
          fail "#{netif_type} network interface mismatch"
        end
      end

      swappable_resources = %i(memory cpu swap)

      primary_resources_obj = primary_vps.get_cluster_resources(swappable_resources)
      secondary_resources_obj = secondary_vps.get_cluster_resources(swappable_resources)

      if opts[:resources]
        primary_resources = {}
        secondary_resources = {}

        swappable_resources.each do |r|
          primary_resources[r] = primary_vps.send(r)
          secondary_resources[r] = secondary_vps.send(r)
        end

        new_primary_resources_obj = secondary_resources_obj
        new_secondary_resources_obj = primary_resources_obj
      end

      # Migrate secondary VPS to primary node.
      # Do not replace IP addresses.
      use_chain(
        Vps::Migrate.chain_for(secondary_vps, primary_vps.node),
        args: [
          secondary_vps,
          primary_vps.node,
          {
            replace_ips: false,
            resources: opts[:resources] ? primary_resources : nil,
            handle_ips: false,
            reallocate_ips: false,
            maintenance_window: false,
            send_mail: false,
          }
        ],
        hooks: {
          pre_start: ->(ret, _, _) do
            # Remove addresses from the secondary (new primary) VPS
            secondary_netifs.each_value do |attrs|
              attrs[:routes].reverse_each do |ip|
                attrs[:host_addrs].reverse_each do |addr|
                  next unless addr.ip_address == ip

                  append_t(
                    Transactions::NetworkInterface::DelHostIp,
                    args: [attrs[:target_netif], addr],
                    urgent: true,
                  ) do |t|
                    t.edit(addr, order: nil)
                  end
                end

                append_t(
                  Transactions::NetworkInterface::DelRoute,
                  args: [attrs[:target_netif], ip, false],
                  urgent: true,
                ) do |t|
                  t.edit(ip, network_interface_id: nil)
                end
              end
            end

            primary_netifs.each do |netif_type, attrs|
              # Remove IP addresses from the original primary VPS.
              attrs[:routes].reverse_each do |ip|
                attrs[:host_addrs].each do |addr|
                  next unless addr.ip_address == ip

                  append_t(
                    Transactions::NetworkInterface::DelHostIp,
                    args: [attrs[:netif], addr],
                    urgent: true,
                  ) do |t|
                    t.edit(addr, order: nil)
                  end
                end

                append_t(
                  Transactions::NetworkInterface::DelRoute,
                  args: [attrs[:netif], ip, true],
                  urgent: true,
                ) do |t|
                  t.edit(ip, network_interface_id: nil)
                end
              end

              # Add IPs from the original primary to the new primary
              dst_attrs = secondary_netifs[netif_type]
              host_i = 0

              attrs[:routes].each do |ip|
                append_t(
                  Transactions::NetworkInterface::AddRoute,
                  args: [dst_attrs[:target_netif], ip, true],
                  kwargs: {via: ip.route_via},
                  urgent: true,
                ) do |t|
                  t.edit(ip, network_interface_id: dst_attrs[:target_netif].id)
                end

                attrs[:host_addrs].each do |addr|
                  next unless addr.ip_address == ip

                  append_t(
                    Transactions::NetworkInterface::AddHostIp,
                    args: [dst_attrs[:target_netif], addr],
                    urgent: true,
                  ) do |t|
                    t.edit(addr, order: host_i)
                    host_i += 1
                  end
                end
              end
            end

            if opts[:resources]
              if same_env
                resources = new_primary_vps.reallocate_resources(
                  primary_resources,
                  new_primary_vps.user,
                  chain: self
                )

              else
                resources = []

                new_primary_resources_obj.each do |use|
                  use.value = primary_resources[use.user_cluster_resource.cluster_resource.name.to_sym]
                  use.attr_changes = {value: use.value}
                  resources << use
                end
              end

              use_chain(Vps::SetResources, args: [
                new_primary_vps, resources
              ], urgent: true)

            else  # Resources are not swapped, re-set the original ones
              append(Transactions::Vps::Resources, args: [
                new_primary_vps,
                secondary_resources_obj
              ])
            end

            if opts[:hostname] && new_primary_vps.manage_hostname
              append(Transactions::Vps::Hostname,
                args: [
                  new_primary_vps,
                  secondary_vps.hostname,
                  primary_vps.hostname
                ],
                urgent: true
              ) do
                edit(new_primary_vps, hostname: primary_vps.hostname)
              end
            end

            ret
          end
        }
      )

      # In case the second migration fails, prevent rollback of the first migration
      append_t(Transactions::Utils::NoOp, args: find_node_id, reversible: :not_reversible)

      # At this point, the new primary VPS is complete. Migrate the original
      # primary VPS to the secondary node, where it becomes the new secondary
      # VPS.
      use_chain(
        Vps::Migrate.chain_for(primary_vps, secondary_vps.node),
        args: [
          primary_vps,
          secondary_vps.node,
          {
            replace_ips: false,
            resources: opts[:resources] ? secondary_resources : nil,
            handle_ips: false,
            reallocate_ips: false,
            maintenance_window: false,
            send_mail: false,
          }
        ],
        hooks: {
          pre_start: ->(ret, _, _) do
            # Add IP addresses to the new secondary VPS
            secondary_netifs.each do |netif_type, attrs|
              dst_attrs = primary_netifs[netif_type]
              host_i = 0

              attrs[:routes].each do |ip|
                append_t(
                  Transactions::NetworkInterface::AddRoute,
                  args: [dst_attrs[:target_netif], ip, true],
                  kwargs: {via: ip.route_via},
                  urgent: true,
                ) do |t|
                  t.edit(ip, network_interface_id: dst_attrs[:target_netif].id)
                end

                attrs[:host_addrs].each do |addr|
                  next unless addr.ip_address == ip

                  append_t(
                    Transactions::NetworkInterface::AddHostIp,
                    args: [dst_attrs[:target_netif], addr],
                    urgent: true,
                  ) do |t|
                    t.edit(addr, order: host_i)
                    host_i += 1
                  end
                end
              end
            end

            if opts[:resources]
              if same_env
                resources = new_secondary_vps.reallocate_resources(
                  secondary_resources,
                  new_secondary_vps.user,
                  chain: self
                )

              else
                resources = []

                new_secondary_resources_obj.each do |use|
                  use.value = secondary_resources[use.user_cluster_resource.cluster_resource.name.to_sym]
                  use.attr_changes = {value: use.value}
                  resources << use
                end
              end

              use_chain(Vps::SetResources, args: [
                new_secondary_vps, resources
              ], urgent: true)

            else  # Resources are not swapped, re-set the original ones
              append(Transactions::Vps::Resources, args: [
                new_secondary_vps,
                primary_resources_obj
              ])
            end

            if opts[:hostname] && new_secondary_vps.manage_hostname
              append(Transactions::Vps::Hostname,
                args: [
                  new_secondary_vps,
                  primary_vps.hostname,
                  secondary_vps.hostname
                ],
                urgent: true
              ) do
                edit(new_secondary_vps, hostname: secondary_vps.hostname)
              end
            end

            ret
          end
        }
      )

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        if faked_resources.count > 0
          faked_resources.each do |use|
            t.edit(use, confirmed: ::ClusterResourceUse.confirmed(:confirmed))
          end
        end

        # Expirations
        if opts[:expirations]
          fmt = '%Y-%m-%d %H:%M:%S'
          t.edit(
            new_primary_vps,
            expiration_date: primary_vps.expiration_date && \
                              primary_vps.expiration_date.utc.strftime(fmt)
          )
          t.edit(
            new_secondary_vps,
            expiration_date: secondary_vps.expiration_date && \
                              secondary_vps.expiration_date.utc.strftime(fmt)
          )
        end

        t.just_create(new_primary_vps.log(:swap, new_secondary_vps.id))
        t.just_create(new_secondary_vps.log(:swap, new_primary_vps.id))
      end

      # fail 'all done!'
    end

    def recursive_serialize(dataset, children, pool)
      ret = []

      # First parents
      dip = dataset.dataset_in_pools.where(pool: pool).take

      return ret unless dip

      lock(dip)
      ret.concat(dip.free_resources(chain: self))

      # Then children
      children.each do |k, v|
        if v.is_a?(::Dataset)
          dip = v.dataset_in_pools.where(pool: pool).take
          next unless dip

          lock(dip)
          ret.concat(dip.free_resources(chain: self))

        else
          ret.concat(recursive_serialize(k, v, pool))
        end
      end

      ret
    end
  end
end
