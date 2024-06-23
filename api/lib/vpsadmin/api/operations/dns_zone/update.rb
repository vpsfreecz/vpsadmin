require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::Update < Operations::Base
    # @param dns_zone [::DnsZone]
    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsZone)]
    def run(dns_zone, attrs)
      TransactionChains::DnsZone::Update.fire2(args: [dns_zone, attrs])
    end
  end
end
