require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Enable < Operations::Base
    # @param device [::UserTotpDevice]
    # @return [::UserTotpDevice]
    def run(device)
      unless device.confirmed
        raise Exceptions::OperationError, 'unconfirmed device cannot be enabled'
      end

      device.update!(enabled: true)
      device
    end
  end
end
