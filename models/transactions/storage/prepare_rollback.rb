module Transactions::Storage
  class PrepareRollback < ::Transaction
    t_name :storage_prepare_rollback
    t_type 5209

    def params(dataset_in_pool)
      self.t_server = dataset_in_pool.pool.node_id

      {
          pool_fs: dataset_in_pool.pool.filesystem,
          dataset_name: dataset_in_pool.dataset.name
      }
    end
  end
end
