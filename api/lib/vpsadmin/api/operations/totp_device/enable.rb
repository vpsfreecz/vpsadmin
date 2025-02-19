require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Enable < Operations::Base
    # @param device [::UserTotpDevice]
    # @return [::UserTotpDevice]
    def run(device)
      raise Exceptions::OperationError, 'unconfirmed device cannot be enabled' unless device.confirmed

      device.update!(enabled: true)
      device.user.update!(enable_multi_factor_auth: true) unless device.user.enable_multi_factor_auth
      device
    end
  end
end
