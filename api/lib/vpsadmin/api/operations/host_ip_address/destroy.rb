require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::HostIpAddress::Destroy < Operations::Base
    event_policy :transaction_chain,
                 reason: 'covered by transaction-chain operation lifecycle events',
                 atomic: false
    # @param host_ip_address [HostIpAddress]
    # @return [::TransactionChain, nil]
    def run(host_ip_address)
      if !host_ip_address.user_created
        raise Exceptions::OperationError, "#{host_ip_address.ip_addr} cannot be deleted"
      elsif host_ip_address.assigned?
        raise Exceptions::OperationError, "#{host_ip_address.ip_addr} is in use"
      end

      TransactionChains::HostIpAddress::Destroy.fire(host_ip_address)
    end
  end
end
