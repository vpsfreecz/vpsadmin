require 'rotp'
require 'securerandom'
require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::User::TotpConfirm < Operations::Base
    # @param user [::User]
    # @param code [String]
    # @return [String] recovery code
    def run(user, code)
      if user.totp_enabled
        raise Exceptions::OperationError, 'totp authentication already enabled'
      elsif user.totp_secret.nil?
        raise Exceptions::OperationError, 'totp authentication not enabled'
      end

      totp = ROTP::TOTP.new(user.totp_secret)

      unless totp.verify(code)
        raise Exceptions::OperationError, 'invalid totp code'
      end

      recovery_code = SecureRandom.hex(15)

      user.update!(
        totp_enabled: true,
        totp_recovery_code: CryptoProviders::Bcrypt.encrypt(nil, recovery_code),
      )

      recovery_code
    end
  end
end
