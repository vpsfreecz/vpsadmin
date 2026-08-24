require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Delete < Operations::Base
    # @param device [::UserTotpDevice]
    def run(device)
      Operations::Authentication::MfaFactorChange.run(
        device,
        revoke_recovery: true
      ) do |locked_device, _user|
        locked_device.destroy!
      end
    end
  end
end
