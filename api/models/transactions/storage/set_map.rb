module Transactions::Storage
  class SetMap < ::Transaction
    t_name :storage_set_map
    t_type 5225
    queue :storage

    include Transactions::Utils::UserNamespaces

    def params(dataset_in_pools_with_maps)
      if dataset_in_pools_with_maps.empty?
        raise ArgumentError, 'provide at least one dataset in pool'
      end

      first_dip = dataset_in_pools_with_maps.first[0]

      dataset_in_pools_with_maps.each do |dip, map|
        if dip.pool_id != first_dip.pool_id
          raise ArgumentError, 'dataset in pools must be from the same pool'
        end
      end

      self.node_id = first_dip.pool.node_id

      datasets = dataset_in_pools_with_maps.map do |dataset_in_pool, userns_map|
        {
          pool_fs: dataset_in_pool.pool.filesystem,
          name: dataset_in_pool.dataset.full_name,
          new: userns_map && {
            uidmap: build_map(userns_map, :uid).join(','),
            gidmap: build_map(userns_map, :gid).join(','),
          },
          original: dataset_in_pool.user_namespace_map && {
            uidmap: build_map(dataset_in_pool.user_namespace_map, :uid).join(','),
            gidmap: build_map(dataset_in_pool.user_namespace_map, :gid).join(','),
          }
        }
      end

      {
        datasets: datasets,
      }
    end
  end
end
