require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Enable < Operations::Base
    # @param device [::UserTotpDevice]
    # @return [::UserTotpDevice]
    def run(device)
      Operations::Authentication::MfaFactorChange.run(device) do |locked_device, user|
        unless locked_device.confirmed
          raise Exceptions::OperationError, 'unconfirmed device cannot be enabled'
        end

        locked_device.update!(enabled: true)
        user.update!(enable_multi_factor_auth: true) unless user.enable_multi_factor_auth
        locked_device
      end
    end
  end
end
