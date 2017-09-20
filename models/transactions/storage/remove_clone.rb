module Transactions::Storage
  class RemoveClone < ::Transaction
    t_name :storage_remove_clone
    t_type 5218
    queue :storage

    def params(snapshot_in_pool)
      self.node_id = snapshot_in_pool.dataset_in_pool.pool.node_id

      {
          pool_fs: snapshot_in_pool.dataset_in_pool.pool.filesystem,
          dataset_name: snapshot_in_pool.dataset_in_pool.dataset.full_name,
          snapshot_id: snapshot_in_pool.snapshot_id,
          snapshot: snapshot_in_pool.snapshot.name
      }
    end
  end
end
