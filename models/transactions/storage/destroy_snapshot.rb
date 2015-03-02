module Transactions::Storage
  class DestroySnapshot < ::Transaction
    t_name :storage_destroy_snapshot
    t_type 5212
    irreversible

    def params(snapshot_in_pool, branch = nil)
      self.t_server = snapshot_in_pool.dataset_in_pool.pool.node_id

      ret = {
          pool_fs: snapshot_in_pool.dataset_in_pool.pool.filesystem,
          dataset_name: snapshot_in_pool.dataset_in_pool.dataset.full_name,
          snapshot: {
              id: snapshot_in_pool.snapshot_id,
              name: snapshot_in_pool.snapshot.name,
              confirmed: snapshot_in_pool.snapshot.confirmed
          }
      }

      if branch
        ret[:tree] = branch.dataset_tree.full_name
        ret[:branch] = branch.full_name
      end

      ret
    end
  end
end
