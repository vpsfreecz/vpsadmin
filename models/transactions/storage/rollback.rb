module Transactions::Storage
  # Do a local zfs rollback. Destroys all datasets newer than
  # the one roll backing to.
  class Rollback < ::Transaction
    t_name :storage_rollback
    t_type 5208
    irreversible

    def params(dataset_in_pool, snapshot_in_pool)
      self.t_server = dataset_in_pool.pool.node_id

      {
          pool_fs: dataset_in_pool.pool.filesystem,
          dataset_name: dataset_in_pool.dataset.full_name,
          snapshot: snapshot_in_pool.snapshot.name
      }
    end
  end
end
