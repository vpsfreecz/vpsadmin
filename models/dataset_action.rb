class DatasetAction < ActiveRecord::Base
  references :pool
  belongs_to :src_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :dst_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :last_transaction, class_name: 'Transaction'

  enum action: %i(snapshot transfer rollback)

  def execute
    case action.to_sym
      when :snapshot
        src_dataset_in_pool.snapshot

      when :transfer
        src_dataset_in_pool.transfer(dst_dataset_in_pool)

      when :rollback
        src_dataset_in_pool.rollback
    end
  end
end
