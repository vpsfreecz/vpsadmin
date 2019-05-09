require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::User::TotpDisable < Operations::Base
    # @param user [::User]
    # @return [true]
    def run(user)
      if !user.totp_enabled && !user.totp_secret
        raise Exceptions::OperationError, 'totp authentication not enabled'
      end

      user.update!(
        totp_enabled: false,
        totp_secret: nil,
        totp_recovery_code: nil,
      )
      true
    end
  end
end
