require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Environment::Update < Operations::Base
    event_policy :resource, models: [::Environment, ::EnvironmentUserConfig]
    # @param export [::Environment]
    # @param attrs [Hash]
    # @return [::Environment]
    def run(env, attrs)
      env.assign_attributes(attrs)

      ::Environment.transaction do
        env.save!

        propagated = {
          can_create_vps: env.can_create_vps,
          can_destroy_vps: env.can_destroy_vps,
          vps_lifetime: env.vps_lifetime,
          max_vps_count: env.max_vps_count
        }
        configs = env.environment_user_configs.where(default: true).to_a
        configs_with_changes = configs.filter_map do |config|
          changed_fields = propagated.keys.reject do |field|
            config.public_send(field) == propagated[field]
          end
          [config, changed_fields] if changed_fields.any?
        end

        env.environment_user_configs.where(id: configs.map(&:id)).update_all(
          propagated
        )
        configs_with_changes.each do |config, changed_fields|
          VpsAdmin::API::Events::ActionPolicies.record(
            :updated,
            config,
            changed_fields:
          )
        end
      end

      env
    end
  end
end
