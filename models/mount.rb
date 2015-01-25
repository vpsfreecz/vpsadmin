class Mount < ActiveRecord::Base
  belongs_to :vps
  belongs_to :dataset_in_pool
  belongs_to :snapshot_in_pool

  validate :check_mountpoint

  include Confirmable
  include Lockable

  def check_mountpoint
    if dst !~ /\A[a-zA-Z0-9_\-\/\.]{3,500}\z/ || dst =~ /\.\./ || dst =~ /\/\//
      errors.add(:dst, 'invalid format')
    end

    if self.class.where(vps: vps, dst: dst).exists?
      errors.add(:dst, 'this mountpoint already exists')
    end
  end

  def dataset
    dataset_in_pool_id && dataset_in_pool.dataset
  end

  def snapshot
    snapshot_in_pool_id && snapshot_in_pool.snapshot
  end
end
