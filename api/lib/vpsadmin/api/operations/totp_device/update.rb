require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Update < Operations::Base
    # @param device [::UserTotpDevice]
    # @param attrs [Hash]
    # @option attrs [String] :label
    # @return [::UserTotpDevice]
    def run(device, attrs)
      device.update!(label: attrs[:label])
      device
    end
  end
end
