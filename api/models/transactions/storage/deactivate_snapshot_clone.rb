module Transactions::Storage
  class DeactivateSnapshotClone < ::Transaction
    t_name :storage_deactivate_snapshot_clone
    t_type 5227
    queue :storage

    # @param cl [::SnapshotInPoolClone]
    def params(cl)
      self.node_id = cl.snapshot_in_pool.dataset_in_pool.pool.node_id

      {
        clone_name: cl.name,
        pool_fs: cl.snapshot_in_pool.dataset_in_pool.pool.filesystem
      }
    end
  end
end
