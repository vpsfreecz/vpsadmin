require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZoneTransfer::Create < Operations::Base
    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsZoneTransfer)]
    def run(attrs)
      zone_transfer = ::DnsZoneTransfer.new(**attrs)

      TransactionChains::DnsZoneTransfer::Create.fire2(args: [zone_transfer])
    end
  end
end
