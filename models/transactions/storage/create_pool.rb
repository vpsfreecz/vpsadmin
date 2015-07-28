module Transactions::Storage
  class CreatePool < ::Transaction
    t_name :storage_create_pool
    t_type 5250

    def params(pool, properties)
      self.t_server = pool.node_id

      {
          pool_fs: pool.filesystem,
          options: properties
      }
    end
  end
end
