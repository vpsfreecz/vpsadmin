module TransactionChains
  class User::Create < ::TransactionChain
    label 'Create user'
    allow_empty

    def link_chain(user, create_vps, node, tpl, activate = true)
      user.save!
      lock(user)
      concerns(:affect, [user.class.name, user.id])

      objects = [user]

      # Create environment configs
      ::Environment.all.each do |env|
        objects << ::EnvironmentUserConfig.create!(
          environment: env,
          user: user,
          can_create_vps: env.can_create_vps,
          can_destroy_vps: env.can_destroy_vps,
          vps_lifetime: env.vps_lifetime,
          max_vps_count: env.max_vps_count
        )

        # Create all cluster resources in all environments
        ::ClusterResource.all.each do |cr|
          objects << ::UserClusterResource.create!(
            user: user,
            environment: env,
            cluster_resource: cr,
            value: 0,
          )
        end

        # Create an empty personal resource package for every environment
        personal_pkg = ::ClusterResourcePackage.create!(
          user: user,
          environment: env,
          label: 'Personal package',
        )
        objects << personal_pkg
        objects << ::UserClusterResourcePackage.create!(
          user: user,
          environment: env,
          cluster_resource_package: personal_pkg,
        )

        # Assign default resource packages
        env.default_user_cluster_resource_packages.each do |pkg|
          objects << ::UserClusterResourcePackage.create!(
            user: user,
            environment: env,
            cluster_resource_package: pkg.cluster_resource_package,
            comment: 'User was created',
          )
        end

        user.calculate_cluster_resources_in_env(env)
      end

      unless activate
        user.record_object_state_change(:suspended, chain: self)
        user.object_state = 'suspended'
      end

      # Create a default VPS group
      objects << ::VpsGroup.create!(
        user: user,
        label: 'Default group',
        group_type: 'group_none',
      )

      ret = user.call_class_hooks_for(
        :create,
        self,
        args: [user],
        initial: {objects: []}
      )
      objects.concat(ret[:objects])

      if create_vps
        vps = ::Vps.new(
          user: user,
          node: node,
          os_template: tpl,
          hostname: 'vps',
          config: '',
        )
        vps.dns_resolver = ::DnsResolver.pick_suitable_resolver_for_vps(vps)

        vps_opts = {
          start: activate,
        }

        node.location.environment.default_object_cluster_resources.joins(
          :cluster_resource
        ).where(
          class_name: 'Vps',
          cluster_resources: {name: %w(ipv4 ipv4_private ipv6)},
        ).each do |default|
          vps_opts[ default.cluster_resource.name.to_sym ] = default.value
        end

        use_chain(Vps::Create, args: [vps, vps_opts])
      end

      unless empty?
        append(Transactions::Utils::NoOp, args: find_node_id) do
          objects.each { |o| just_create(o) }
        end
      end

      mail(:user_create, {
        user: user,
        vars: {
          user: user
        }
      })

      user
    end
  end
end
