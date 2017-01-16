module Transactions::Storage
  class PrepareRollback < ::Transaction
    t_name :storage_prepare_rollback
    t_type 5209
    queue :storage

    def params(dataset_in_pool)
      self.node_id = dataset_in_pool.pool.node_id

      {
          pool_fs: dataset_in_pool.pool.filesystem,
          dataset_name: dataset_in_pool.dataset.full_name
      }
    end
  end
end
