require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsServer::AddZone < Operations::Base
    # @param dns_server [::DnsServer]
    # @param dns_zone [::DnsZone]
    # @return [Array(::TransactionChain, ::DnsServerZone)]
    def run(dns_server, dns_zone)
      dns_server_zone = ::DnsServerZone.new(
        dns_server:,
        dns_zone:
      )

      TransactionChains::DnsZone::Create.fire2(args: [dns_server_zone])
    end
  end
end
