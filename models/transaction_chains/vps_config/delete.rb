module TransactionChains
  class VpsConfig::Delete < ::TransactionChain
    label 'Delete'

    def link_chain(cfg)
      lock(cfg)
      concerns(:affect, [cfg.class.name, cfg.id])

      ::Node.where(server_type: 'node').each do |n|
        append(Transactions::Hypervisor::DeleteConfig, args: [n, cfg])
      end
      
      append(Transactions::Utils::NoOp, args: find_node_id) do
        just_destroy(cfg)
      end

      cfg
    end
  end
end
