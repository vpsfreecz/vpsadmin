module Transactions::Storage
  class EnsureUgidOffset < ::Transaction
    t_name :storage_ensure_ugid_offset
    t_type 5225
    queue :storage

    def params(dataset_in_pool)
      self.node_id = dataset_in_pool.pool.node_id

      {
        pool_fs: dataset_in_pool.pool.filesystem,
        name: dataset_in_pool.dataset.full_name,
        uidoffset: dataset_in_pool.user_namespace.offset,
        gidoffset: dataset_in_pool.user_namespace.offset,
      }
    end
  end
end
