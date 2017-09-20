module Transactions::Vps
  # Create /vz/root/<veid>
  class CreateRoot < ::Transaction
    t_name :vps_create_root
    t_type 4002

    def params(vps, dst_node)
      self.vps_id = vps.id
      self.node_id = dst_node.id

      {}
    end
  end
end
