class SnapshotInPool < ActiveRecord::Base
  belongs_to :snapshot
  belongs_to :dataset_in_pool
  has_many :snapshot_in_pool_in_branches
end
