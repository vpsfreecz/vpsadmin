module TransactionChains
  class VpsConfig::Create < ::TransactionChain
    label 'Create'

    def link_chain(cfg)
      cfg.save! unless cfg.id
      concerns(:affect, [cfg.class.name, cfg.id])

      ::Node.where(server_type: 'node').each do |n|
        append(Transactions::Hypervisor::CreateConfig, args: [n, cfg])
      end

      cfg
    end
  end
end
