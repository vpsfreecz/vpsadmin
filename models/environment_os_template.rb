class EnvironmentOsTemplate < ActiveRecord::Base
  belongs_to :environment
  belongs_to :os_template
  has_paper_trail
end
