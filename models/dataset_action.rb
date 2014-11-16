class DatasetAction < ActiveRecord::Base
  belongs_to :pool
  belongs_to :src_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :dst_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :last_transaction, class_name: 'Transaction'
  has_many :group_snapshots

  enum action: %i(snapshot transfer rollback backup group_snapshot)

  def execute
    case action.to_sym
      when :snapshot
        src_dataset_in_pool.snapshot

      when :transfer
        src_dataset_in_pool.transfer(dst_dataset_in_pool)

      when :rollback
        src_dataset_in_pool.rollback

      when :backup
        src_dataset_in_pool.backup(dst_dataset_in_pool)

      when :group_snapshot
        do_group_snapshots
    end
  end

  def do_group_snapshots
    dips = []

    group_snapshots.all.each do |s|
      dips << s.dataset_in_pool
    end

    TransactionChains::Dataset::GroupSnapshot.fire(dips) unless dips.count == 0
  end
end
