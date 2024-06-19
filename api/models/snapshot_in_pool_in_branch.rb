require_relative 'confirmable'
require_relative 'lockable'

class SnapshotInPoolInBranch < ApplicationRecord
  belongs_to :snapshot_in_pool
  belongs_to :branch
  belongs_to :snapshot_in_pool_in_branch

  include Confirmable
  include Lockable
end
