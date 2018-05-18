module Transactions::Vps
  class SetMap < ::Transaction
    t_name :vps_set_map
    t_type 2021
    queue :vps

    include Transactions::Utils::UserNamespaces

    def params(vps, userns_map)
      self.node_id = vps.node_id
      self.vps_id = vps.id

      {
        new: {
          userns_map: userns_map.id.to_s,
          uidmap: build_map(userns_map, :uid),
          gidmap: build_map(userns_map, :gid),
        },
        original: {
          userns_map: vps.userns_map.id.to_s,
          uidmap: build_map(vps.userns_map, :uid),
          gidmap: build_map(vps.userns_map, :gid),
        },
      }
    end
  end
end
