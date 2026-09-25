module Transactions::Storage
  class DestroyDataset < ::Transaction
    t_name :storage_destroy_dataset
    t_type 5203
    storage_effect :filesystem_destroy
    queue :storage
    irreversible

    def params(dataset_in_pool)
      self.node_id = dataset_in_pool.pool.node_id

      {
        pool_fs: dataset_in_pool.pool.filesystem,
        name: dataset_in_pool.dataset.full_name
      }
    end
  end
end
