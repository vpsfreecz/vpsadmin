require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Update < Operations::Base
    # @param device [::UserTotpDevice]
    # @param attrs [Hash]
    # @option attrs [String] :label
    # @return [::UserTotpDevice]
    def run(device, attrs)
      Operations::Authentication::MfaFactorChange.run(device) do |locked_device, _user|
        locked_device.update!(label: attrs[:label])
        locked_device
      end
    end
  end
end
