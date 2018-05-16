module Transactions::UserNamespace
  class DestroyMap < ::Transaction
    t_name :userns_map_destroy
    t_type 7002
    queue :general

    include Transactions::Utils::UserNamespaces

    def params(node, userns_map)
      self.node_id = node.id

      {
        name: userns_map.id.to_s,
        ugid: userns_map.ugid,
        uidmap: build_map(userns_map, :uid),
        gidmap: build_map(userns_map, :gid),
      }
    end
  end
end
