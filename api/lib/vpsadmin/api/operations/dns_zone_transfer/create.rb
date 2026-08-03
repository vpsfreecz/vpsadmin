require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZoneTransfer::Create < Operations::Base
    event_policy :transaction_chain,
                 reason: 'covered by transaction-chain operation lifecycle events',
                 atomic: false
    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsZoneTransfer)]
    def run(attrs)
      zone_transfer = ::DnsZoneTransfer.new(**attrs)

      TransactionChains::DnsZoneTransfer::Create.fire2(args: [zone_transfer])
    end
  end
end
