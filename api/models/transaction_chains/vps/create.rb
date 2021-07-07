module TransactionChains
  class Vps::Create < ::TransactionChain
    label 'Create'

    # @param opts [Hash]
    # @option opts [Integer] ipv4
    # @option opts [Integer] ipv6
    # @option opts [Integer] ipv4_private
    # @option opts [Boolean] start (true)
    # @Option opts [::UserNamespaceMap, nil] userns_map
    # @Option opts [::Location, nil] address_location
    def link_chain(vps, opts)
      lock(vps.user)
      vps.save!
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      vps_resources = vps.allocate_resources(
        required: %i(cpu memory swap),
        optional: [],
        user: vps.user,
        chain: self
      )

      if vps.node.vpsadminos?
        userns_map = opts[:userns_map] || ::UserNamespaceMap.joins(:user_namespace).where(
          user_namespaces: {user_id: vps.user_id}
        ).take!

        use_chain(UserNamespaceMap::Use, args: [userns_map, vps.node])

      else
        userns_map = nil
      end

      pool = vps.node.pools.where(role: 'hypervisor').take!

      ds = ::Dataset.new(
        name: vps.id.to_s,
        user: vps.user,
        user_editable: false,
        user_create: true,
        user_destroy: false,
        confirmed: ::Dataset.confirmed(:confirm_create)
      )

      dip = use_chain(Dataset::Create, args: [
        pool,
        nil,
        [ds],
        automount: false,
        properties: {refquota: vps.diskspace},
        user: vps.user,
        label: "vps#{vps.id}",
        userns_map: userns_map,
      ]).last

      vps.dataset_in_pool = dip

      lock(vps.dataset_in_pool)

      vps_features = []

      append(Transactions::Vps::Create, args: vps) do
        create(vps)
        just_create(vps.current_object_state)

        # Create features
        ::VpsFeature::FEATURES.each do |name, f|
          next unless f.support?(vps.node)

          feature = ::VpsFeature.create!(vps: vps, name: name, enabled: false)
          vps_features << feature
          just_create(feature)
        end

        # Maintenance windows
        7.times do |i|
          w = VpsMaintenanceWindow.new(
            vps: vps,
            weekday: i,
            is_open: true,
            opens_at: 60,
            closes_at: 5*60,
          )
          w.save!(validate: false)
          just_create(w)
        end
      end

      if vps.node.openvz?
        use_chain(Vps::ApplyConfig, args: [
          vps,
          vps.node.location.environment.vps_configs.pluck(:id)
        ])
      end

      # Set default features
      vps_features.each { |f| f.set_to_default }

      if vps_features.any?(&:changed?)
        use_chain(Vps::Features, args: [vps, vps_features])
      end

      # Create network interface
      if vps.node.vpsadminos?
        netif = use_chain(
          NetworkInterface::VethRouted::Create,
          args: [vps, 'venet0']
        )

      else
        netif = use_chain(NetworkInterface::Venet::Create, args: vps)
      end

      # Add IP addresses
      versions = [:ipv4, :ipv4_private]
      versions << :ipv6 if vps.node.location.has_ipv6

      ip_resources = []
      user_env = vps.user.environment_user_configs.find_by!(
        environment: vps.node.location.environment,
      )

      versions.each do |v|
        next if opts[v].nil? || opts[v] <= 0

        n = use_chain(
          Ip::Allocate,
          args: [
            ::ClusterResource.find_by!(name: v),
            netif,
            opts[v],
            host_addrs: true,
            address_location: opts[:address_location],
          ],
          method: :allocate_to_netif,
        )
        ip_resources << user_env.reallocate_resource!(
          v,
          user_env.send(v) + n,
          user: vps.user,
          chain: self,
        )
      end

      if ip_resources.size > 0
        append(Transactions::Utils::NoOp, args: vps.node_id) do
          ip_resources.each do |r|
            if r.updating?
              edit(r, r.attr_changes)

            else
              create(r)
            end
          end
        end
      end

      vps.dns_resolver ||= ::DnsResolver.pick_suitable_resolver_for_vps(vps)

      append(Transactions::Vps::DnsResolver, args: [
        vps,
        vps.dns_resolver,
        vps.dns_resolver
      ])

      use_chain(Vps::SetResources, args: [vps, vps_resources])

      vps.user.user_public_keys.where(auto_add: true).each do |key|
        use_chain(Vps::DeployPublicKey, args: [vps, key])
      end

      if vps.onboot && (!opts.has_key?(:start) || opts[:start])
        use_chain(TransactionChains::Vps::Start, args: vps)
      end

      vps.save!

      concerns(:affect, [vps.class.name, vps.id])

      vps
    end
  end
end
