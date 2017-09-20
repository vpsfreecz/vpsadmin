class DefaultObjectClusterResource < ActiveRecord::Base
  belongs_to :environment
  belongs_to :cluster_resource
end
