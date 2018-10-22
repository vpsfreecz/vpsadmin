module Transactions::Storage
  # Do a local zfs rollback. Destroys all datasets newer than
  # the one roll backing to.
  class Rollback < ::Transaction
    t_name :storage_rollback
    t_type 5208
    queue :storage
    irreversible

    def params(dataset_in_pool, snapshot_in_pool)
      self.node_id = dataset_in_pool.pool.node_id

      children = []

      ::Dataset.descendants_of(dataset_in_pool.dataset)
        .joins(:dataset_in_pools)
        .where(
          dataset_in_pools: {pool: dataset_in_pool.pool}
        ).order('full_name').each do |ds|
        children << {
          name: ds.name,
          full_name: ds.full_name,
        }
      end

      {
        pool_fs: dataset_in_pool.pool.filesystem,
        dataset_name: dataset_in_pool.dataset.full_name,
        snapshot: snapshot_in_pool.snapshot.name,
        descendant_datasets: children,
      }
    end
  end
end
