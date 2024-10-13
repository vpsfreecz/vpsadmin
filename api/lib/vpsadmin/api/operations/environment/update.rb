require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Environment::Update < Operations::Base
    # @param export [::Environment]
    # @param attrs [Hash]
    # @return [::Environment]
    def run(env, attrs)
      env.assign_attributes(attrs)

      self.class.transaction do
        env.save!

        env.environment_user_configs.where(default: true).update_all(
          can_create_vps: env.can_create_vps,
          can_destroy_vps: env.can_destroy_vps,
          vps_lifetime: env.vps_lifetime,
          max_vps_count: env.max_vps_count
        )
      end

      env
    end
  end
end
