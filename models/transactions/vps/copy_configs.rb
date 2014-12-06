module Transactions::Vps
  class CopyConfigs < ::Transaction
    t_name :vps_copy_configs
    t_type 4001

    def params(vps, dst_node)
      self.t_vps = vps.vps_id
      self.t_server = dst_node.id

      {
          src_node_addr: vps.node.addr
      }
    end
  end
end
