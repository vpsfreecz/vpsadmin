class DatasetInPool < ActiveRecord::Base
  belongs_to :dataset
  belongs_to :pool
  has_many :snapshot_in_pools
  has_many :dataset_trees
  has_many :mounts

  validate :check_mountpoint

  include Lockable
  include Confirmable
  include HaveAPI::Hookable

  has_hook :create

  def check_mountpoint
    if mountpoint.present?
      if mountpoint !~ /\A[a-zA-Z0-9_\-\/\.]{3,500}\z/ || mountpoint =~ /\.\./
        errors.add(:mountpoint, 'invalid format')
      end
    end
  end

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
