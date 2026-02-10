class ClusterResource < ApplicationRecord
  has_many :default_object_cluster_resources

  enum :resource_type, %i[numeric object]

  validates :name, presence: true, uniqueness: true
  validates :label, presence: true
  validates :min, presence: true
  validates :max, presence: true
  validates :stepsize, presence: true
  validates :resource_type, presence: true
end
