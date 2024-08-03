require 'vpsadmin/api/operations/base'
require_relative 'record_utils'

module VpsAdmin::API
  class Operations::DnsZone::CreateRecord < Operations::Base
    include Operations::DnsZone::RecordUtils

    # @param attrs [Hash]
    # @return [Array(::TransactionChain, ::DnsRecord)]
    def run(attrs)
      dyn_enable = attrs.delete(:dynamic_update_enabled)
      dns_record = ::DnsRecord.new(**process_record(attrs))

      if dns_record.dns_zone.managed
        raise Exceptions::ZoneManagedError, dns_record.dns_zone
      elsif !%w[A AAAA].include?(dns_record.record_type)
        raise Exceptions::OperationError, 'Only A and AAAA records can utilize dynamic updates'
      end

      unless dns_record.valid?
        raise ActiveRecord::RecordInvalid, dns_record
      end

      if dyn_enable
        ::Token.for_new_record! do |t|
          dns_record.update_token = t
          dns_record.save!
          dns_record
        end
      else
        dns_record.save!
      end

      TransactionChains::DnsZone::CreateRecord.fire(dns_record)
    end
  end
end
