module Transactions::Storage
  class SetMap < ::Transaction
    t_name :storage_set_map
    t_type 5225
    queue :storage

    include Transactions::Utils::UserNamespaces

    def params(dataset_in_pool, userns_map)
      self.node_id = dataset_in_pool.pool.node_id

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
  end
end
