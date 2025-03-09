module TransactionChains
  class Vps::Create < ::TransactionChain
    label 'Create'

    # @param opts [Hash]
    # @option opts [Integer] ipv4
    # @option opts [Integer] ipv6
    # @option opts [Integer] ipv4_private
    # @option opts [Boolean] start (true)
    # @option opts [::Location, nil] address_location
    # @option opts [::VpsUserData] user_data
    def link_chain(vps, opts)
      lock(vps.user)
      vps.save!
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      vps_resources = vps.allocate_resources(
        required: %i[cpu memory swap],
        optional: [],
        user: vps.user,
        chain: self
      )

      pool = ::Pool.take_by_node!(vps.node, role: :hypervisor)

      vps.user_namespace_map ||= ::UserNamespaceMap.joins(:user_namespace).where(
        user_namespaces: { user_id: vps.user_id }
      ).take!

      ds = ::Dataset.new(
        name: vps.id.to_s,
        user: vps.user,
        vps:,
        user_editable: false,
        user_create: true,
        user_destroy: false,
        confirmed: ::Dataset.confirmed(:confirm_create)
      )

      dip = use_chain(Dataset::Create, args: [
                        pool,
                        nil,
                        [ds],
                        {
                          automount: false,
                          properties: { refquota: dataset_refquota(vps, '/') },
                          user: vps.user,
                          label: "vps#{vps.id}",
                          userns_map: vps.map_mode == 'zfs' ? vps.user_namespace_map : nil
                        }
                      ]).last

      vps.dataset_in_pool = dip

      lock(vps.dataset_in_pool)

      template_subdatasets = vps.os_template.datasets.reject do |v|
        v['name'] == '/'
      end

      vps_subdips = template_subdatasets.to_h do |subds_opts|
        subds = ::Dataset.new(
          parent: ds,
          name: subds_opts['name'],
          user: vps.user,
          vps:,
          user_editable: false,
          user_create: true,
          user_destroy: false,
          confirmed: ::Dataset.confirmed(:confirm_create)
        )

        subdip = use_chain(Dataset::Create, args: [
                             pool,
                             nil,
                             [subds],
                             {
                               automount: false,
                               properties: { refquota: dataset_refquota(vps, subds_opts['name']) },
                               user: vps.user,
                               userns_map: vps.map_mode == 'zfs' ? vps.user_namespace_map : nil
                             }
                           ]).last

        lock(subdip)

        [subds_opts['name'], subdip]
      end

      use_chain(UserNamespaceMap::Use, args: [vps, vps.user_namespace_map])

      #  Setup template mounts
      template_mounts = vps.os_template.mounts

      mounts = template_mounts.map do |tpl_mnt|
        mount_dip =
          if tpl_mnt['dataset'] == '/'
            vps.dataset_in_pool
          else
            vps_subdips[tpl_mnt['dataset']]
          end

        if mount_dip.nil?
          raise "Unable to create mount of #{tpl_mnt['dataset']} in " \
                "OS template #{vps.os_template.label}: dataset not found"
        end

        ::Mount.create!(
          vps:,
          dst: tpl_mnt['mountpoint'],
          mount_opts: '--bind',
          umount_opts: '-f',
          mount_type: 'bind',
          mode: 'rw',
          user_editable: true,
          dataset_in_pool: mount_dip
        )
      end

      vps_features = []

      append(Transactions::Vps::Create, args: vps) do
        create(vps)
        just_create(vps.current_object_state)

        mounts.each do |mnt|
          create(mnt)

          just_create(vps.log(:mount, {
                              id: mnt.id,
                              type: :dataset,
                              src: {
                                id: mnt.dataset_in_pool.dataset_id,
                                name: mnt.dataset_in_pool.dataset.full_name
                              },
                              dst: mnt.dst,
                              mode: mnt.mode,
                              on_start_fail: mnt.on_start_fail,
                              enabled: mnt.enabled
                            }))
        end

        # Create features
        ::VpsFeature::FEATURES.each do |name, f|
          next unless f.support?(vps.node)

          feature = ::VpsFeature.create!(vps:, name:, enabled: false)
          vps_features << feature
          just_create(feature)
        end

        # Maintenance windows
        7.times do |i|
          w = VpsMaintenanceWindow.new(
            vps:,
            weekday: i,
            is_open: true,
            opens_at: 60,
            closes_at: 5 * 60
          )
          w.save!(validate: false)
          just_create(w)
        end
      end

      use_chain(Vps::Mounts, args: [vps, mounts]) if mounts.any?

      # Set default features
      template_features = vps.os_template.features

      vps_features.each do |feature|
        if template_features.has_key?(feature.name)
          feature.enabled = template_features[feature.name]
        else
          feature.set_to_default
        end
      end

      use_chain(Vps::Features, args: [vps, vps_features]) if vps_features.any?(&:changed?)

      # Create network interface
      netif = if vps.node.vpsadminos?
                use_chain(
                  NetworkInterface::VethRouted::Create,
                  args: [vps, 'venet0']
                )

              else
                use_chain(NetworkInterface::Venet::Create, args: vps)
              end

      # Add IP addresses
      versions = %i[ipv4 ipv4_private]
      versions << :ipv6 if vps.node.location.has_ipv6

      ip_resources = []
      user_env = vps.user.environment_user_configs.find_by!(
        environment: vps.node.location.environment
      )

      versions.each do |v|
        next if opts[v].nil? || opts[v] <= 0

        n = use_chain(
          Ip::Allocate,
          args: [
            ::ClusterResource.find_by!(name: v),
            netif,
            opts[v]
          ],
          kwargs: {
            host_addrs: true,
            address_location: opts[:address_location]
          },
          method: :allocate_to_netif
        )
        ip_resources << user_env.reallocate_resource!(
          v,
          user_env.send(v) + n,
          user: vps.user,
          chain: self
        )
      end

      unless ip_resources.empty?
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

      if vps.os_template.manage_dns_resolver
        vps.dns_resolver ||= ::DnsResolver.pick_suitable_resolver_for_vps(vps)

        append(Transactions::Vps::DnsResolver, args: [
                 vps,
                 vps.dns_resolver,
                 vps.dns_resolver
               ])
      end

      use_chain(Vps::SetResources, args: [vps, vps_resources])

      vps.user.user_public_keys.where(auto_add: true).each do |key|
        use_chain(Vps::DeployPublicKey, args: [vps, key])
      end

      if opts[:vps_user_data]
        append_t(Transactions::Vps::DeployUserData, args: [vps, opts[:vps_user_data]])
      end

      use_chain(TransactionChains::Vps::Start, args: vps) if opts.fetch(:start, true)

      vps.save!

      concerns(:affect, [vps.class.name, vps.id])

      vps
    end

    protected

    def dataset_refquota(vps, lookup_name)
      tpl_ds = vps.os_template.datasets.detect do |v|
        v['name'] == lookup_name
      end
      tpl_ds ||= {}

      refquota = tpl_ds.fetch('properties', {}).fetch('refquota', nil)

      if refquota.nil?
        return vps.diskspace if lookup_name == '/'

        raise "OS template #{vps.os_template.label} is missing refquota option for dataset #{dataset.name}"
      end

      if refquota.is_a?(Integer)
        refquota
      elsif /\A(\d+)%\z/ =~ refquota
        (vps.diskspace / 100.0 * Regexp.last_match(1).to_i).floor
      else
        raise "OS template #{vps.os_template.label} has unknown refquota format: #{refquota.inspect}"
      end
    end
  end
end
