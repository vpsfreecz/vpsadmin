class ClusterResourcePackageItem < ActiveRecord::Base
  belongs_to :cluster_resource_package
  belongs_to :cluster_resource
end
