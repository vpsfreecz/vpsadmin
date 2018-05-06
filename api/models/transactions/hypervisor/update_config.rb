module Transactions::Hypervisor
  class UpdateConfig < ::Transaction
    t_name :hypervisor_update_config
    t_type 7303

    def params(node, cfg)
      self.node_id = node.id

      {
        original: {
          name: cfg.name_was,
          vps_config: cfg.config_was,
        },
        new: {
          name: cfg.name,
          vps_config: cfg.config,
        },
      }
    end
  end
end
