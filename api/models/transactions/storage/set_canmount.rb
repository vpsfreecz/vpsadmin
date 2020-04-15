module Transactions::Storage
  class SetCanmount < ::Transaction
    t_name :storage_set_canmount
    t_type 5228
    queue :storage

    def params(dataset_in_pools, canmount: nil, mount: false)
      self.node_id = dataset_in_pools.first.pool.node_id

      pool_fs = dataset_in_pools.first.pool.filesystem

      {
        pool_fs: pool_fs,
        datasets: dataset_in_pools.map do |dip|
          if dip.pool.node_id != node_id
            fail 'mismatching node_id'
          elsif dip.pool.filesystem != pool_fs
            fail 'mismatching pool_fs'
          end

          dip.dataset.full_name
        end.sort,
        canmount: canmount || (raise ArgumentError, 'missing canmount'),
        mount: mount,
      }
    end
  end
end
