class Mount < ActiveRecord::Base
  belongs_to :vps
  belongs_to :dataset_in_pool
  belongs_to :snapshot_in_pool

  validate :check_mountpoint

  include Confirmable
  include Lockable

  include VpsAdmin::API::Lifetimes::Model
  set_object_states states: %i(active deleted),
                    deleted: {
                      enter: TransactionChains::Vps::DestroyMount
                    }

  enum on_start_fail: %i(skip mount_later fail_start wait_for_mount)
  enum current_state: %i(created mounted unmounted skipped delayed waiting)

  def check_mountpoint
    dst.insert(0, '/') unless dst.start_with?('/')
    dst.chop! while dst.end_with?('/')

    if dst !~ /\A[a-zA-Z0-9_\-\/\.]{3,500}\z/ || dst =~ /\.\./ || dst =~ /\/\//
      errors.add(:dst, 'invalid format')
    end

    cnt = self.class.where(vps: vps, dst: dst).count

    if (new_record? && cnt > 0) || (!new_record? && cnt > 1)
      errors.add(:dst, 'this mountpoint already exists')
    end
  end

  def enabled?
    enabled && master_enabled
  end

  def dataset
    dataset_in_pool && dataset_in_pool.dataset
  end

  def snapshot
    snapshot_in_pool && snapshot_in_pool.snapshot
  end

  def update_chain(attrs)
    TransactionChains::Vps::UpdateMount.fire(self, attrs)
  end
end
