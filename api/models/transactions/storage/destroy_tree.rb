module Transactions::Storage
  class DestroyTree < ::Transaction
    t_name :storage_destroy_dataset_tree
    t_type 5214
    storage_effect :tree_destroy
    queue :storage
    irreversible

    def params(tree)
      self.node_id = tree.dataset_in_pool.pool.node_id

      {
        pool_fs: tree.dataset_in_pool.pool.filesystem,
        dataset_name: tree.dataset_in_pool.dataset.full_name,
        tree: tree.full_name
      }
    end
  end
end
