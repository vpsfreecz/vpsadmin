class UserClusterResource < ActiveRecord::Base
  belongs_to :user
  belongs_to :environment
  belongs_to :cluster_resource
end
