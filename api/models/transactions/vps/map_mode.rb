module Transactions::Vps
  class MapMode < ::Transaction
    t_name :vps_map_mode
    t_type 2034
    queue :vps

    def params(vps, original_map_mode)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        new_map_mode: vps.map_mode,
        original_map_mode: original_map_mode
      }
    end
  end
end
