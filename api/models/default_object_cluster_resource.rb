class DefaultObjectClusterResource < ApplicationRecord
  belongs_to :environment
  belongs_to :cluster_resource

  validates :environment, presence: true
  validates :cluster_resource, presence: true
  validates :class_name, presence: true
  validates :value, presence: true
end
