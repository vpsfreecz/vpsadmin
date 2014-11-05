module Transactions::Hypervisor
  class DeleteConfig < ::Transaction
    t_name :hypervisor_delete_config
    t_type 7302

    def params(node, cfg)
      self.t_server = node.id

      {
          name: cfg.name
      }
    end
  end
end
