module TransactionChains
  # This chain does nothing by default. It is used to call hooks
  # for user creation.
  class User::Create < ::TransactionChain
    label 'Create user'
    allow_empty

    def link_chain(user)
      user.save!

      # Create environment configs
      ::Environment.all.each do |env|
        ::EnvironmentUserConfig.create!(
            environment: env,
            user: user,
            can_create_vps: env.can_create_vps,
            can_destroy_vps: env.can_destroy_vps,
            vps_lifetime: env.vps_lifetime,
            max_vps_count: env.max_vps_count
        )
      end

      user.call_class_hooks_for(:create, self, args: [user])
    end
  end
end
