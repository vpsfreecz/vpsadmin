module TransactionChains
  class VpsConfig::Create < ::TransactionChain
    label 'Create'

    def link_chain(cfg)
      cfg.save! unless cfg.id
      lock(cfg)
      concerns(:affect, [cfg.class.name, cfg.id])

      ::Node.where(role: 'node').each do |n|
        append(Transactions::Hypervisor::CreateConfig, args: [n, cfg])
      end

      append(Transactions::Utils::NoOp, args: find_node_id) do
        just_create(cfg)
      end

      cfg
    end
  end
end
