require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::HostIpAddress::Create < Operations::Base
    # @param ip_address [IpAddress]
    # @param host_addr [String]
    # @return [::HostIpAddress]
    def run(ip_address, host_addr, actor: nil)
      begin
        parsed_addr = IPAddress.parse(host_addr)
      rescue ArgumentError
        raise Exceptions::OperationError, 'Unable to parse IP address'
      end

      ip_address.with_current_lock(actor:) do
        unless ip_address.include?(parsed_addr)
          raise Exceptions::OperationError, "#{parsed_addr} does not belong to #{ip_address}"
        end

        begin
          ::HostIpAddress.create!(
            ip_address:,
            ip_addr: parsed_addr.to_s,
            order: nil,
            user_created: true
          )
        rescue ::ActiveRecord::RecordNotUnique
          raise Exceptions::OperationError, "#{parsed_addr} already exists"
        end
      end
    end
  end
end
