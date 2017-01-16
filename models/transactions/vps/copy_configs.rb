module Transactions::Vps
  class CopyConfigs < ::Transaction
    t_name :vps_copy_configs
    t_type 4001

    def params(vps, dst_node, dst_vps = nil)
      self.vps_id = vps.vps_id
      self.node_id = dst_node.id

      {
          src_node_addr: vps.node.addr,
          local: vps.vps_server == dst_node.id,
          dst_vps: (dst_vps && dst_vps.id) || vps.vps_id
      }
    end
  end
end
