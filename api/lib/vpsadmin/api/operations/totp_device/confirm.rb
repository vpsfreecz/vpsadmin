require 'securerandom'
require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Confirm < Operations::Base
    # @param device [::UserTotpDevice]
    # @param code [String]
    # @return [String] recovery code
    def run(device, code)
      raise Exceptions::OperationError, 'the device is already confirmed' if device.confirmed

      raise Exceptions::OperationError, 'invalid totp code' unless device.totp.verify(code)

      recovery_code = SecureRandom.hex(20)

      device.update!(
        confirmed: true,
        enabled: true,
        recovery_code: CryptoProviders::Bcrypt.encrypt(nil, recovery_code)
      )

      recovery_code
    end
  end
end
