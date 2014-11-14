module Transactions::Storage
  class ApplyRollback < ::Transaction
    t_name :storage_apply_rollback
    t_type 5211

    def params(dataset_in_pool)
      self.t_server = dataset_in_pool.pool.node_id

      children = []

      Dataset.children_of(dataset_in_pool.dataset)
        .joins(:dataset_in_pools)
        .where(dataset_in_pools: {pool: dataset_in_pool.pool}) do |ds|
        children << ds.name
      end

      {
          pool_fs: dataset_in_pool.pool.filesystem,
          dataset_name: dataset_in_pool.dataset.full_name,
          child_datasets: children
      }
    end
  end
end
