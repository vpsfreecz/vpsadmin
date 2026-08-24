require 'securerandom'
require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Confirm < Operations::Base
    # @param device [::UserTotpDevice]
    # @param code [String]
    # @return [String] recovery code
    def run(device, code)
      Operations::Authentication::MfaFactorChange.run(device) do |locked_device, user|
        if locked_device.confirmed
          raise Exceptions::OperationError, 'the device is already confirmed'
        end

        unless locked_device.totp.verify(code)
          raise Exceptions::OperationError, 'invalid totp code'
        end

        recovery_code = SecureRandom.hex(20)

        locked_device.update!(
          confirmed: true,
          enabled: true,
          recovery_code: CryptoProviders::Bcrypt.encrypt(nil, recovery_code)
        )

        user.update!(enable_multi_factor_auth: true) unless user.enable_multi_factor_auth

        recovery_code
      end
    end
  end
end
