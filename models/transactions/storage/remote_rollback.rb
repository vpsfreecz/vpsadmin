module Transactions::Storage
  class RemoteRollback < ::Transaction
    t_name :storage_remote_rollback
    t_type 5210

    def params(dataset_in_pool, snapshot_in_pool)
      self.t_server = snapshot_in_pool.dataset_in_pool.pool.node_id

      tree = snapshot_in_pool.dataset_in_pool.dataset_trees.find_by!(head: true)

      {
          primary_node_addr: dataset_in_pool.pool.node.addr,
          primary_pool_fs: dataset_in_pool.pool.filesystem,
          backup_pool_fs: snapshot_in_pool.dataset_in_pool.pool.filesystem,
          tree: tree.full_name,
          branch: tree.branches.find_by!(head: true).full_name,
          dataset_name: dataset_in_pool.dataset.full_name,
          snapshot: snapshot_in_pool.snapshot.name
      }
    end
  end
end
