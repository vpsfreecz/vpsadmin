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

      host_ip = nil
      ::IpAddress.transaction(requires_new: true) do
        ip_address.acquire_lock do
          ip_address.reload(lock: true)
          ip_address.ensure_owner!(actor) if actor
          unless ip_address.include?(parsed_addr)
            raise Exceptions::OperationError, "#{parsed_addr} does not belong to #{ip_address}"
          end

          begin
            host_ip = ::HostIpAddress.create!(
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

      host_ip
    end
  end
end
