require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsServer::RemoveZone < Operations::Base
    # @param dns_server_zone [::DnsServerZone]
    # @return [::TransactionChain]
    def run(dns_server_zone)
      chain, = TransactionChains::DnsZone::Destroy.fire2(args: [dns_server_zone])
      chain
    end
  end
end
