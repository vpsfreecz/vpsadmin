class Pool < ActiveRecord::Base
  belongs_to :node
  has_many :dataset_in_pools
  has_many :dataset_properties
  has_many :dataset_actions

  enum role: %i(hypervisor primary backup)
end
