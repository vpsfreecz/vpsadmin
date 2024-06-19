class DefaultObjectClusterResource < ApplicationRecord
  belongs_to :environment
  belongs_to :cluster_resource
end
