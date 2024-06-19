require_relative 'confirmable'
require_relative 'lockable'

class SnapshotInPool < ApplicationRecord
  belongs_to :snapshot
  belongs_to :dataset_in_pool
  belongs_to :mount
  has_many :snapshot_in_pool_in_branches
  has_many :mounts

  include Confirmable
  include Lockable
end
