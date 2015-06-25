class EnvironmentUserConfig < ActiveRecord::Base
  belongs_to :environment
  belongs_to :user

  def update!(attrs)
    if attrs[:default]
      attrs = {
          default: true,
          can_create_vps: environment.can_create_vps,
          can_destroy_vps: environment.can_destroy_vps,
          vps_lifetime: environment.vps_lifetime,
          max_vps_count: environment.max_vps_count
      }

    else
      attrs[:default] = false
    end
    
    super(attrs)
  end
end
