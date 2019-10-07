require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Export::AddHost < Operations::Base
    # @param export [::Export]
    # @param ip_address [::IpAddress]
    # @return [TransactionChain, ExportHost]
    def run(export, ip_address)
      chain, hosts = TransactionChains::Export::AddHosts.fire(export, [ip_address])
      return chain, hosts.first
    end
  end
end
