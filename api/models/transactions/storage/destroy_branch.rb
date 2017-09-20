module Transactions::Storage
  class DestroyBranch < ::Transaction
    t_name :storage_destroy_branch
    t_type 5207
    queue :storage
    irreversible

    def params(branch)
      self.node_id = branch.dataset_tree.dataset_in_pool.pool.node_id

      {
          pool_fs: branch.dataset_tree.dataset_in_pool.pool.filesystem,
          dataset_name: branch.dataset_tree.dataset_in_pool.dataset.full_name,
          tree: branch.dataset_tree.full_name,
          branch: branch.full_name
      }
    end
  end
end
