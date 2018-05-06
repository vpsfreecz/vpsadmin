module Transactions::Storage
  class RecvCheck < ::Transaction
    t_name :storage_recv_check
    t_type 5222
    queue :storage

    def params(dst, snapshots, branch = nil, ds_suffix = nil)
      self.node_id = dst.pool.node_id

      {
        dst_pool_fs: dst.pool.filesystem,
        dataset_name: ds_suffix ? "#{dst.dataset.full_name}.#{ds_suffix}" : dst.dataset.full_name,
        snapshot: {
          id: snapshots.last.snapshot_id,
          name: snapshots.last.snapshot.name,
          confirmed: snapshots.last.snapshot.confirmed
        },
        tree: branch && branch.dataset_tree.full_name,
        branch: branch && branch.full_name,
      }
    end
  end
end
