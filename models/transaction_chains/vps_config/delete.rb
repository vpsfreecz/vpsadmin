module TransactionChains
  class VpsConfig::Delete < ::TransactionChain
    label 'Delete config'

    def link_chain(cfg)
      ::Node.where(server_type: 'node').each do |n|
        append(Transactions::Hypervisor::DeleteConfig, args: [n, cfg])
      end

      cfg
    end
  end
end
