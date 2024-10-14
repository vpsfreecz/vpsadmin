class DatasetAction < ApplicationRecord
  belongs_to :pool
  belongs_to :src_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :dst_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :dataset_plan
  belongs_to :dataset_in_pool_plan
  has_many :group_snapshots

  enum action: %i[snapshot transfer rollback backup group_snapshot]

  def execute
    case action.to_sym
    when :snapshot
      TransactionChains::Dataset::Snapshot.fire(src_dataset_in_pool)

    when :transfer
      TransactionChains::Dataset::Transfer.fire(src_dataset_in_pool, dst_dataset_in_pool)

    when :rollback
      raise 'not supported'

    when :backup
      TransactionChains::Dataset::Backup.fire(src_dataset_in_pool, dst_dataset_in_pool)

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

    TransactionChains::Dataset::GroupSnapshot.fire(dips) unless dips.count == 0
  end
end
