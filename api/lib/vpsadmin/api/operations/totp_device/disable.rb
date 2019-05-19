require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Disable < Operations::Base
    # @param device [::UserTotpDevice]
    # @return [::UserTotpDevice]
    def run(device)
      device.update!(enabled: false)
      device
    end
  end
end
