require 'vpsadmin/api/operations/base'
require_relative 'record_utils'

module VpsAdmin::API
  class Operations::DnsZone::UpdateRecord < Operations::Base
    include Operations::DnsZone::RecordUtils

    # @param dns_record [::DnsRecord]
    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsRecord)]
    def run(dns_record, attrs)
      dns_record.assign_attributes(process_record(attrs, record_type: dns_record.record_type))

      unless dns_record.valid?
        raise ActiveRecord::RecordInvalid, dns_record
      end

      TransactionChains::DnsZone::UpdateRecord.fire(dns_record)
    end
  end
end
