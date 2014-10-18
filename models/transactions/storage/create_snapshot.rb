module Transactions::Storage
  class CreateSnapshot < ::Transaction
    t_name :storage_create_snapshot
    t_type 5204

    def params(snapshot_in_pool)
      self.t_server = snapshot_in_pool.dataset_in_pool.pool.node_id

      {
          pool_fs: snapshot_in_pool.dataset_in_pool.pool.filesystem,
          dataset_name: snapshot_in_pool.dataset_in_pool.dataset.full_name,
          snapshot_id: snapshot_in_pool.snapshot_id
      }
    end
  end
end
