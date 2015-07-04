module TransactionChains
  class User::Create < ::TransactionChain
    label 'Create user'
    allow_empty

    def link_chain(user, create_vps, node, tpl)
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


        env.default_object_cluster_resources.where(
            class_name: user.class.name
        ).each do |d|
          objects << ::UserClusterResource.create!(
              user: user,
              environment: env,
              cluster_resource: d.cluster_resource,
              value: d.value
          )
        end
      end

      user.call_class_hooks_for(:create, self, args: [user])

      if create_vps
        vps = ::Vps.new(
            user: user,
            node: node,
            os_template: tpl,
            hostname: 'vps',
            vps_backup_export: 0,
            vps_backup_exclude: '',
            vps_config: ''
        )
        vps.dns_resolver = DnsResolver.pick_suitable_resolver_for_vps(vps)

        use_chain(Vps::Create, args: [vps, true])
      end

      unless empty?
        append(Transactions::Utils::NoOp, args: ::Node.first_available.id) do
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
