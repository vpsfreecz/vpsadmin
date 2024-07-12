require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::DestroySystem < Operations::Base
    # @param dns_zone [::DnsZone]
    def run(dns_zone)
      if dns_zone.dns_server_zones.any?
        raise Exceptions::OperationError,
              'DNS zone is in use, remove it from all servers first'
      end

      dns_zone.destroy!
      nil
    end
  end
end
