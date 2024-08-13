require 'vpsadmin/api/operations/base'
require_relative 'record_utils'
require 'ipaddress'

module VpsAdmin::API
  class Operations::DnsZone::DynamicUpdate < Operations::Base
    # @param request [Sinatra::Request]
    # @param update_token [String]
    # @yieldparam dns_record [::DnsRecord]
    # @return [Array(::TransactionChain, ::DnsRecord)]
    def run(request, update_token)
      dns_record = ::DnsRecord.joins(:update_token).find_by!(
        tokens: { token: update_token },
        record_type: %w[A AAAA]
      )

      yield(dns_record) if block_given?

      client_ip_addr = request.env['HTTP_CLIENT_IP'] || request.env['HTTP_X_REAL_IP'] || request.ip

      begin
        addr = IPAddress.parse(client_ip_addr)
      rescue ArgumentError
        raise Exceptions::OperationError, 'Unable to parse client IP address'
      end

      if dns_record.record_type == 'A' && !addr.ipv4?
        raise Exceptions::OperationError, 'Record is of type A and client address is IPv6'
      elsif dns_record.record_type == 'AAAA' && !addr.ipv6?
        raise Exceptions::OperationError, 'Record is of type AAAA and client address is IPv4'
      end

      dns_record.content = addr.to_s

      unless dns_record.valid?
        raise ActiveRecord::RecordInvalid, dns_record
      end

      TransactionChains::DnsZone::UpdateRecord.fire(dns_record)
    end
  end
end
