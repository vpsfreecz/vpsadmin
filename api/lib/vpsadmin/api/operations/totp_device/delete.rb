require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Delete < Operations::Base
    # @param device [::UserTotpDevice]
    def run(device)
      device.destroy!
    end
  end
end
