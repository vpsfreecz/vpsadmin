class DatasetInPool < ActiveRecord::Base
  belongs_to :dataset
  belongs_to :pool
  has_many :snapshot_in_pools
  has_many :branches
  has_many :mounts

  include Lockable

  def snapshot
    TransactionChains::Dataset::Snapshot.fire(self)
  end

  # +dst+ is destination DatasetInPool.
  def transfer(dst)
    TransactionChains::Dataset::Transfer.fire(self, dst)
  end

  def rollback(snap)
    TransactionChains::Dataset::Rollback.fire(self, snap)
  end

  def backup(dst)
    TransactionChains::Dataset::Backup.fire(self, dst)
  end
end
