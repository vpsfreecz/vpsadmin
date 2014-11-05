module Transactions::Hypervisor
  class CreateConfig < ::Transaction
    t_name :hypervisor_create_config
    t_type 7301

    def params(node, cfg)
      self.t_server = node.id

      ret = {
          name: cfg.name,
          vps_config: cfg.config
      }

      ret[:old_name] = cfg.name_was if cfg.name_changed?

      ret
    end
  end
end
