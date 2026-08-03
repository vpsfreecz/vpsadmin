require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Delete < Operations::Base
    event_policy :resource, models: [::UserTotpDevice]
    # @param device [::UserTotpDevice]
    def run(device)
      device.destroy!
    end
  end
end
