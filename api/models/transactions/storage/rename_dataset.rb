module Transactions::Storage
  class RenameDataset < ::Transaction
    t_name :storage_rename_dataset
    t_type 5230
    queue :storage

    def params(pool, old_name, new_name)
      self.node_id = pool.node_id

      {
        pool_fs: pool.filesystem,
        old_name:,
        new_name:
      }
    end
  end
end
