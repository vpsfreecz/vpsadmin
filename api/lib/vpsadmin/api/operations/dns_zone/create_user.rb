require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::CreateUser < Operations::Base
    # @param attrs [Hash]
    # @return [Array(TransactionChain, ::DnsZone)]
    def run(attrs)
      dns_zone = ::DnsZone.new(**attrs)
      dns_zone.user = ::User.current unless ::User.current.role == :admin

      unless dns_zone.valid?
        raise ActiveRecord::RecordInvalid, dns_zone
      end

      TransactionChains::DnsZone::CreateUser.fire2(args: [dns_zone])
    end
  end
end
