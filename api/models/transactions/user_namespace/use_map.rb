module Transactions::UserNamespace
  class UseMap < ::Transaction
    t_name :userns_map_use
    t_type 7001
    queue :general

    include Transactions::Utils::UserNamespaces

    def params(vps, userns_map)
      self.node_id = vps.node_id
      self.vps_id = vps.id

      {
        pool_fs: vps.dataset_in_pool.pool.filesystem,
        name: userns_map.id.to_s,
        uidmap: build_map(userns_map, :uid),
        gidmap: build_map(userns_map, :gid),
      }
    end
  end
end
