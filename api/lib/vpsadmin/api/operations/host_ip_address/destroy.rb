require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::HostIpAddress::Destroy < Operations::Base
    # @param host_ip_address [HostIpAddress]
    def run(host_ip_address)
      if !host_ip_address.user_created
        raise Exceptions::OperationError, "#{host_ip_address.ip_addr} cannot be deleted"
      elsif host_ip_address.assigned?
        raise Exceptions::OperationError, "#{host_ip_address.ip_addr} is in use"
      end

      host_ip_address.destroy!
      nil
    end
  end
end
