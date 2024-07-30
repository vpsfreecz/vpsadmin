require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::DestroyRecord < Operations::Base
    # @param dns_record [::DnsRecord]
    # @return [::TransactionChain]
    def run(dns_record)
      chain, = TransactionChains::DnsZone::DestroyRecord.fire(dns_record)
      chain
    end
  end
end
