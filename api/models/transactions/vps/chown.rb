module Transactions::Vps
  class Chown < ::Transaction
    t_name :vps_chown
    t_type 3041
    queue :vps

    # @param vps [::Vps]
    # @param current_userns_map [::UserNamespaceMap]
    # @param new_userns_map [::UserNamespaceMap]
    def params(vps, current_userns_map, new_userns_map)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        original_user_id: current_userns_map.user_namespace.user_id,
        original_userns_map: current_userns_map.id.to_s,
        new_user_id: new_userns_map.user_namespace.user_id,
        new_userns_map: new_userns_map.id.to_s
      }
    end
  end
end
