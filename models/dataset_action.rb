class DatasetAction < ActiveRecord::Base
  references :pool
  belongs_to :src_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :dst_dataset_in_pool, class_name: 'DatasetInPool'
  belongs_to :last_transaction, class_name: 'Transaction'

  enum action: %i(snapshot transfer rollback)
end
