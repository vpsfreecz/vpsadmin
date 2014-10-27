module Transactions::Storage
  class CreateTree < ::Transaction
    t_name :storage_create_dataset_tree
    t_type 5213

    def params(tree)
      self.t_server = tree.dataset_in_pool.pool.node_id

      {
          pool_fs: tree.dataset_in_pool.pool.filesystem,
          dataset_name: tree.dataset_in_pool.dataset.full_name,
          tree: tree.full_name
      }
    end
  end
end
