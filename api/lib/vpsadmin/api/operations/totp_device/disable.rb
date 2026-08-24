require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Disable < Operations::Base
    # @param device [::UserTotpDevice]
    # @return [::UserTotpDevice]
    def run(device)
      Operations::Authentication::MfaFactorChange.run(
        device,
        revoke_recovery: true
      ) do |locked_device, _user|
        locked_device.update!(enabled: false)
        locked_device
      end
    end
  end
end
