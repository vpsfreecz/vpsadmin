module TransactionChains
  class VpsConfig::Create < ::TransactionChain
    label 'Create config'

    def link_chain(cfg)
      cfg.save! unless cfg.id

      ::Node.where(server_type: 'node').each do |n|
        append(Transactions::Hypervisor::CreateConfig, args: [n, cfg])
      end

      cfg
    end
  end
end
