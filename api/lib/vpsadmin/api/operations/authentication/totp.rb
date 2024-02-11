require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::Totp < Operations::Base
    Result = Struct.new(:user, :auth_token, :recovery_device, :reset_password) do
      def authenticated?
        !auth_token.nil?
      end

      def used_recovery_code?
        !recovery_device.nil?
      end

      alias_method :reset_password?, :reset_password
    end

    # @param token [String]
    # @param code [String]
    # @return [Result]
    def run(token, code)
      auth_token = ::AuthToken.joins(:token).includes(:token, :user).find_by(
        tokens: { token: },
        purpose: 'totp'
      )

      raise Exceptions::AuthenticationError, 'invalid token' if auth_token.nil? || !auth_token.token_valid?

      user = auth_token.user

      user.user_totp_devices.where(enabled: true).order('last_use_at DESC').each do |dev|
        last_verification_at = dev.totp.verify(code, after: dev.last_verification_at)

        next unless last_verification_at || is_recovery_code?(dev, code)

        if last_verification_at
          dev.update!(
            last_verification_at:,
            last_use_at: Time.now
          )
          ::UserTotpDevice.increment_counter(:use_count, dev.id)
        else
          # Recovery code was used, disable the device
          dev.update!(enabled: false)
        end

        reset_password = user.password_reset

        if reset_password
          auth_token.update!(purpose: 'reset_password')
        else
          auth_token.destroy!
        end

        return Result.new(
          user,
          auth_token,
          last_verification_at ? nil : dev,
          reset_password
        )
      end

      Result.new(user, nil, nil)
    end

    protected

    def is_recovery_code?(dev, code)
      CryptoProviders::Bcrypt.matches?(dev.recovery_code, nil, code)
    end
  end
end
