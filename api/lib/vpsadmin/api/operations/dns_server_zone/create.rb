require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsServerZone::Create < Operations::Base
    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsServerZone)]
    def run(attrs)
      dns_server_zone = ::DnsServerZone.new(attrs)
      raise ActiveRecord::RecordInvalid, dns_server_zone unless dns_server_zone.valid?

      TransactionChains::DnsServerZone::Create.fire2(args: [dns_server_zone])
    end
  end
end
