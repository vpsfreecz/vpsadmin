module TransactionChains
  class User::Create < ::TransactionChain
    label 'Create user'
    allow_empty

    def link_chain(user)
      user.save!
      lock(user)

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

      unless empty?
        append(Transaction::Utils::NoOp, args: ::Node.first_available.id) do
          objects.each { |o| just_create(o) }
        end
      end

      user
    end
  end
end
