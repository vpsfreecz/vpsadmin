module Transactions::UserNamespace
  class CreateMap < ::Transaction
    t_name :userns_map_create
    t_type 7001
    queue :general

    include Transactions::Utils::UserNamespaces

    def params(pool, userns_map)
      self.node_id = pool.node_id

      {
        pool_name: pool.name,
        name: userns_map.id.to_s,
        ugid: userns_map.ugid,
        uidmap: build_map(userns_map, :uid),
        gidmap: build_map(userns_map, :gid),
      }
    end
  end
end
