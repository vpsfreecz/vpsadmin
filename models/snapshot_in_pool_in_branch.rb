class SnapshotInPoolInBranch < ActiveRecord::Base
  belongs_to :snapshot_in_pool
  belongs_to :branch
  belongs_to :snapshot_in_pool_in_branch

  include Confirmable
end
