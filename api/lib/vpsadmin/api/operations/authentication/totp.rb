require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::Totp < Operations::Base
    Result = Struct.new(:user, :auth_token) do
      def authenticated?
        !auth_token.nil?
      end
    end

    # @param token [String]
    # @param code [String]
    # @return [Result]
    def run(token, code)
      auth_token = ::AuthToken.joins(:token).includes(:token, :user).find_by(
        tokens: {token: token},
      )

      if auth_token.nil? || !auth_token.token_valid?
        raise Exceptions::AuthenticationError, 'invalid token'
      end

      user = auth_token.user

      user.user_totp_devices.order('last_use_at DESC').each do |dev|
        last_verification_at = dev.totp.verify(code, after: dev.last_verification_at)

        if last_verification_at || is_recovery_code?(dev, code)
          if last_verification_at
            dev.update!(
              last_verification_at: last_verification_at,
              last_use_at: Time.now,
            )
            ::UserTotpDevice.increment_counter(:use_count, dev.id)
          end

          auth_token.destroy!
          return Result.new(user, auth_token)
        else
          return Result.new(user, nil)
        end
      end

      Result.new(user, nil)
    end

    protected
    def is_recovery_code?(dev, code)
      CryptoProviders::Bcrypt.matches?(dev.recovery_code, nil, code)
    end
  end
end
