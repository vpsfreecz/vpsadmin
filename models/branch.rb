class Branch < ActiveRecord::Base
  belongs_to :dataset_in_pool
  has_many :snapshot_in_pool_in_branches
end
