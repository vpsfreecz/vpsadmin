class DatasetInPool < ActiveRecord::Base
  belongs_to :dataset
  belongs_to :pool
  has_many :snapshot_in_pools
  has_many :branches
  has_many :mounts

  include Lockable

  def snapshot
    TransactionChains::DatasetSnapshot.fire(self)
  end

  # +dst+ is destination DatasetInPool.
  def transfer(dst)
    TransactionChains::DatasetTransfer.fire(self, dst)
  end

  def rollback(snap)
    TransactionChains::DatasetRollback.fire(self, snap)
  end

  def backup(dst)
    TransactionChains::DatasetBackup.fire(self, dst)
  end
end
