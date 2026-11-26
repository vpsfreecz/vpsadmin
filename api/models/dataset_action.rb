class DatasetAction < ApplicationRecord
  belongs_to :pool
  belongs_to :src_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :dst_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :dataset_plan
  belongs_to :dataset_in_pool_plan
  has_many :group_snapshots

  enum :action, %i[snapshot transfer rollback backup group_snapshot]

  def execute
    case action.to_sym
    when :snapshot
      TransactionChains::Dataset::Snapshot.fire(src_dataset_in_pool, expected_action: id)

    when :transfer
      TransactionChains::Dataset::Transfer.fire(src_dataset_in_pool, dst_dataset_in_pool, expected_action: id)

    when :rollback
      raise 'not supported'

    when :backup
      TransactionChains::Dataset::Backup.fire(src_dataset_in_pool, dst_dataset_in_pool, expected_action: id)

    when :group_snapshot
      do_group_snapshots
    end
  end

  def do_group_snapshots
    dips = []

    group_snapshots.includes(:dataset_in_pool).all.each do |s|
      dip = s.dataset_in_pool

      next unless dip # FIXME: when dataset in pools are deleted, they must be deleted from group snapshot as well!

      dips << dip
    end

    TransactionChains::Dataset::GroupSnapshot.fire(dips, expected_action: id) unless dips.none?
  end

  # Called after the chain acquires its source lock, never on the stale Ruby
  # action loaded by a scheduler worker before plan removal.
  def self.scheduled_for?(id, action:, source:, destination: nil)
    query = where(id: id, action: actions.fetch(action.to_s)).lock
    if action == :group_snapshot
      query.joins(:group_snapshots).where(group_snapshots: { dataset_in_pool_id: source.id }).exists?
    else
      query = query.where(src_dataset_in_pool_id: source.id)
      query = query.where(dst_dataset_in_pool_id: destination.id) if destination
      query.exists?
    end
  end
end
