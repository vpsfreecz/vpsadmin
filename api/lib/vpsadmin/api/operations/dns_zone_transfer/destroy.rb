require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZoneTransfer::Destroy < Operations::Base
    # @param zone_transfer [::DnsZoneTransfer]
    def run(zone_transfer)
      TransactionChains::DnsZoneTransfer::Destroy.fire2(args: [zone_transfer])
    end
  end
end
