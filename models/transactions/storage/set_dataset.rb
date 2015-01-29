module Transactions::Storage
  class SetDataset < ::Transaction
    t_name :storage_set_dataset
    t_type 5216

    def params(dataset_in_pool, changes)
      self.t_server = dataset_in_pool.pool.node_id

      {
          pool_fs: dataset_in_pool.pool.filesystem,
          name: dataset_in_pool.dataset.full_name,
          properties: changes.merge(changes) { |_, v| [v[0].value, v[1]] }
      }
    end
  end
end
