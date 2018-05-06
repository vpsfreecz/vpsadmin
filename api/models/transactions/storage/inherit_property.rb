module Transactions::Storage
  class InheritProperty < ::Transaction
    t_name :storage_inherit_property
    t_type 5219
    queue :storage

    def params(dataset_in_pool, properties)
      self.node_id = dataset_in_pool.pool.node_id

      {
        pool_fs: dataset_in_pool.pool.filesystem,
        name: dataset_in_pool.dataset.full_name,
        properties: properties.merge(properties) { |_, v| v.value },
      }
    end
  end
end
