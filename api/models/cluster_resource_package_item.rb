class ClusterResourcePackageItem < ApplicationRecord
  belongs_to :cluster_resource_package
  belongs_to :cluster_resource

  validates :cluster_resource_package, presence: true
  validates :cluster_resource, presence: true
  validates :value, presence: true
  validates :cluster_resource_id, uniqueness: { scope: :cluster_resource_package_id }
end
