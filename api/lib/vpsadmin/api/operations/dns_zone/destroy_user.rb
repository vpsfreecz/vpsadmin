require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::DestroyUser < Operations::Base
    # @param dns_zone [::DnsZone]
    # @return [::TransactionChain, nil]
    def run(dns_zone)
      chain, = TransactionChains::DnsZone::DestroyUser.fire2(args: [dns_zone])
      chain
    end
  end
end
