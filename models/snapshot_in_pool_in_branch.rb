class SnapshotInPoolInBranch < ActiveRecord::Base
  belongs_to :snapshot_in_pool
  belongs_to :branch
end
