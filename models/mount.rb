class Mount < ActiveRecord::Base
  belongs_to :vps
  belongs_to :dataset_in_pool
  belongs_to :snapshot_in_pool

  include Confirmable
  include Lockable

  def dataset
    dataset_in_pool_id && dataset_in_pool.dataset
  end

  def snapshot
    snapshot_in_pool_id && snapshot_in_pool.snapshot
  end
end
