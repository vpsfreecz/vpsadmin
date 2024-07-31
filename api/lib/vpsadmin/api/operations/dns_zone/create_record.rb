require 'vpsadmin/api/operations/base'
require_relative 'record_utils'

module VpsAdmin::API
  class Operations::DnsZone::CreateRecord < Operations::Base
    include Operations::DnsZone::RecordUtils

    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsRecord)]
    def run(attrs)
      dns_record = ::DnsRecord.new(**process_record(attrs))

      if dns_record.dns_zone.managed
        raise Exceptions::ZoneManagedError, dns_record.dns_zone
      end

      unless dns_record.valid?
        raise ActiveRecord::RecordInvalid, dns_record
      end

      TransactionChains::DnsZone::CreateRecord.fire(dns_record)
    end
  end
end
