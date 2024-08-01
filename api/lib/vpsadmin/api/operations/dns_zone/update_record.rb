require 'vpsadmin/api/operations/base'
require_relative 'record_utils'

module VpsAdmin::API
  class Operations::DnsZone::UpdateRecord < Operations::Base
    include Operations::DnsZone::RecordUtils

    # @param dns_record [::DnsRecord]
    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsRecord)]
    def run(dns_record, attrs)
      if dns_record.dns_zone.managed
        raise Exceptions::ZoneManagedError, dns_record.dns_zone
      end

      dns_record.assign_attributes(process_record(attrs, record_type: dns_record.record_type))

      # If only the comment is changed, we save the record right away
      if dns_record.changed == %w[comment]
        dns_record.save!
        return [nil, dns_record]
      end

      unless dns_record.valid?
        raise ActiveRecord::RecordInvalid, dns_record
      end

      TransactionChains::DnsZone::UpdateRecord.fire(dns_record)
    end
  end
end
