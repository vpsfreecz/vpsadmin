class ClusterResource < ActiveRecord::Base
  has_many :default_object_cluster_resources

  enum resource_type: %i(numeric object)
end
