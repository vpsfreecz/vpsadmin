module Transactions::Hypervisor
  class DeleteConfig < ::Transaction
    t_name :hypervisor_delete_config
    t_type 7302

    def params(node, cfg)
      self.node_id = node.id

      {
          name: cfg.name,
          vps_config: cfg.config
      }
    end
  end
end
