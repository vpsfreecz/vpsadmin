require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::DestroyUser < Operations::Base
    event_policy :transaction_chain,
                 reason: 'covered by transaction-chain operation lifecycle events',
                 atomic: false
    # @param dns_zone [::DnsZone]
    # @return [::TransactionChain, nil]
    def run(dns_zone)
      chain, = TransactionChains::DnsZone::DestroyUser.fire2(args: [dns_zone])
      chain
    end
  end
end
