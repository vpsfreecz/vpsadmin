class DefaultUserClusterResourcePackage < ActiveRecord::Base
  belongs_to :environment
  belongs_to :cluster_resource_package
end
