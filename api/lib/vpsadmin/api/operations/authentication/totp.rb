require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::Totp < Operations::Base
    MAX_FAILED_ATTEMPTS = 5

    class Result
      # @return [::User]
      attr_reader :user

      # @return [::AuthToken]
      attr_reader :auth_token

      # @return [UserTotpDevice, nil]
      attr_reader :recovery_device

      # @return [Boolean]
      attr_reader :reset_password

      # @return [Boolean]
      attr_reader :authenticated

      # @return [Boolean]
      attr_reader :failure_limit_exceeded

      def initialize(user:, auth_token:, recovery_device: nil, reset_password: false, authenticated: false, failure_limit_exceeded: false)
        @user = user
        @auth_token = auth_token
        @recovery_device = recovery_device
        @reset_password = reset_password
        @authenticated = authenticated
        @failure_limit_exceeded = failure_limit_exceeded
      end

      def used_recovery_code?
        !recovery_device.nil?
      end

      alias reset_password? reset_password

      alias authenticated? authenticated

      alias failure_limit_exceeded? failure_limit_exceeded
    end

    # @param token [String]
    # @param code [String]
    # @return [Result]
    def run(token, code)
      auth_token = ::AuthToken.joins(:token).includes(:token, :user).find_by(
        tokens: { token: },
        purpose: 'mfa'
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
          user:,
          auth_token:,
          recovery_device: last_verification_at ? nil : dev,
          reset_password:,
          authenticated: true
        )
      end

      auth_token.with_lock do
        opts = auth_token.opts || {}
        attempts = opts.fetch('totp_failed_attempts', 0).to_i + 1

        if attempts >= MAX_FAILED_ATTEMPTS
          auth_token.destroy!

          Result.new(
            user:,
            auth_token:,
            failure_limit_exceeded: true
          )
        else
          auth_token.update!(
            opts: opts.merge('totp_failed_attempts' => attempts)
          )

          Result.new(user:, auth_token:)
        end
      end
    end

    protected

    def is_recovery_code?(dev, code)
      CryptoProviders::Bcrypt.matches?(dev.recovery_code, nil, code)
    end
  end
end
