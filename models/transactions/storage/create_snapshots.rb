module Transactions::Storage
  class CreateSnapshots < ::Transaction
    t_name :storage_create_snapshots
    t_type 5215
    queue :storage

    def params(snapshot_in_pools)
      self.node_id = snapshot_in_pools.first.dataset_in_pool.pool.node_id

      snapshots = []

      snapshot_in_pools.each do |sip|
        snapshots << {
            pool_fs: sip.dataset_in_pool.pool.filesystem,
            dataset_name: sip.dataset_in_pool.dataset.full_name,
            snapshot_id: sip.snapshot_id
        }
      end

      {
          snapshots: snapshots
      }
    end
  end
end
