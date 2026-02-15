require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Environment::UpdateUserConfig < Operations::Base
    # @param export [::EnvironmentUserConfig]
    # @param attrs [Hash]
    # @return [::EnvironmentUserConfig]
    def run(env_user_cfg, attrs)
      env = env_user_cfg.environment

      if attrs[:default]
        attrs = {
          default: true,
          can_create_vps: env.can_create_vps,
          can_destroy_vps: env.can_destroy_vps,
          vps_lifetime: env.vps_lifetime,
          max_vps_count: env.max_vps_count
        }
      else
        attrs[:default] = false
      end

      env_user_cfg.update!(attrs)
      env_user_cfg
    end
  end
end
