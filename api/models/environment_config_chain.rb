class EnvironmentConfigChain < ActiveRecord::Base
  belongs_to :environment
  belongs_to :vps_config
end
