require 'rotp'
require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::User::TotpEnable < Operations::Base
    Result = Struct.new(:secret, :provisioning_uri)

    # @param user [::User]
    # @return [Result]
    def run(user)
      if user.totp_enabled
        raise Exceptions::OperationError, 'totp authentication already enabled'
      end

      secret = set_secret(user)

      totp = ROTP::TOTP.new(secret, issuer: SysConfig.get(:core, 'totp_issuer'))
      Result.new(secret, totp.provisioning_uri(user.login))
    end

    protected
    def set_secret(user)
      5.times do
        begin
          user.update!(totp_secret: ROTP::Base32.random_base32)
          return user.totp_secret
        rescue ActiveRecord::RecordNotUnique
          next
        end
      end

      raise Exceptions::OperationError, 'unable to generate totp secret'
    end
  end
end
