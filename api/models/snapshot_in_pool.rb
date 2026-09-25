require_relative 'confirmable'
require_relative 'lockable'
require_relative 'storage_snapshot_identity'

class SnapshotInPool < ApplicationRecord
  belongs_to :snapshot
  belongs_to :dataset_in_pool
  belongs_to :mount
  has_many :snapshot_in_pool_in_branches
  has_many :mounts

  include Confirmable
  include Lockable
  include StorageSnapshotIdentity

  private

  def physical_identity_pool_supported?
    dataset_in_pool&.pool && !dataset_in_pool.pool.backup?
  end
end
