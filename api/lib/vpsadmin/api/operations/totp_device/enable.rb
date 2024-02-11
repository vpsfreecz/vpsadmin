require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Enable < Operations::Base
    # @param device [::UserTotpDevice]
    # @return [::UserTotpDevice]
    def run(device)
      raise Exceptions::OperationError, 'unconfirmed device cannot be enabled' unless device.confirmed

      device.update!(enabled: true)
      device
    end
  end
end
