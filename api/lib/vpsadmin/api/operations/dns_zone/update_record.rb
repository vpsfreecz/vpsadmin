require 'vpsadmin/api/operations/base'
require_relative 'record_utils'

module VpsAdmin::API
  class Operations::DnsZone::UpdateRecord < Operations::Base
    include Operations::DnsZone::RecordUtils

    # @param dns_record [::DnsRecord]
    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsRecord)]
    def run(dns_record, attrs)
      if dns_record.managed
        raise Exceptions::DnsRecordManagedError, dns_record
      end

      dyn_enable = attrs.delete(:dynamic_update_enabled)

      if dyn_enable === true && !dns_record.dynamic_update_enabled
        unless %w[A AAAA].include?(dns_record.record_type)
          raise Exceptions::OperationError, 'Only A and AAAA records can utilize dynamic updates'
        end

        ActiveRecord::Base.transaction do
          dns_record.update!(update_token: ::Token.get!(owner: dns_record))
        end

      elsif dyn_enable === false && dns_record.dynamic_update_enabled
        ActiveRecord::Base.transaction do
          token = dns_record.update_token
          dns_record.update!(update_token: nil)
          token.destroy!
        end
      end

      dns_record.assign_attributes(process_record(attrs, record_type: dns_record.record_type))

      # If only the db content is changed, we save the record right away
      if (dns_record.changed - %w[comment user_id original_enabled]).empty?
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
