require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::HostIpAddress::Update < Operations::Base
    # @param host_ip_address [HostIpAddress]
    # @param attrs [Hash]
    # @option attrs [String] :reverse_record_value
    # @return [Array(::TransactionChain, ::HostIpAddress)]
    def run(host_ip_address, attrs)
      ptr_content = attrs.fetch(:reverse_record_value)

      if ptr_content.empty?
        TransactionChains::DnsZone::UnsetReverseRecord.fire2(args: [host_ip_address])
      else
        TransactionChains::DnsZone::SetReverseRecord.fire2(args: [host_ip_address, ptr_content])
      end
    end
  end
end
