module Transactions::Storage
  class CreatePool < ::Transaction
    t_name :storage_create_pool
    t_type 5250
    queue :storage

    def params(pool, properties)
      self.node_id = pool.node_id

      {
        pool_fs: pool.filesystem,
        options: properties,
      }
    end
  end
end
