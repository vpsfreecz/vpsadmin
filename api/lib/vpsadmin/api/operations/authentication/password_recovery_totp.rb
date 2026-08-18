module VpsAdmin::API
  class Operations::Authentication::PasswordRecoveryTotp < Operations::Base
    Result = Struct.new(
      :authenticated,
      :recovery_device,
      :failure_limit_exceeded
    ) do
      alias_method :authenticated?, :authenticated
      alias_method :failure_limit_exceeded?, :failure_limit_exceeded

      def used_recovery_code?
        recovery_device.present?
      end
    end

    def run(recovery, code, request)
      ::PasswordRecovery.transaction do
        user = recovery.user
        user.lock!
        recovery.lock!
        return Result.new(authenticated: false) unless recovery.session_usable?

        user.user_totp_devices.where(
          enabled: true,
          confirmed: true
        ).order('last_use_at DESC').each do |device|
          last_verification_at = device.totp.verify(
            code,
            after: device.last_verification_at
          )
          recovery_code = recovery_code?(device, code)
          next unless last_verification_at || recovery_code

          if last_verification_at
            device.update!(last_verification_at:, last_use_at: Time.current)
            ::UserTotpDevice.increment_counter(:use_count, device.id)
          else
            device.update!(enabled: false)
          end

          recovery.update!(mfa_verified_at: Time.current)

          if recovery_code
            TransactionChains::User::TotpRecoveryCodeUsed.fire(
              user,
              device,
              request
            )
          end

          return Result.new(
            authenticated: true,
            recovery_device: recovery_code ? device : nil,
            failure_limit_exceeded: false
          )
        end

        record_failure(recovery, user, request)
      end
    end

    protected

    def record_failure(recovery, user, request)
      attempts = recovery.totp_failed_attempts + 1
      limit_exceeded = attempts >= ::PasswordRecovery::MAX_TOTP_FAILED_ATTEMPTS
      attrs = { totp_failed_attempts: attempts }
      attrs[:invalidated_at] = Time.current if limit_exceeded
      recovery.update!(attrs)

      Operations::User::FailedLogin.run(
        user,
        :totp,
        'invalid totp code during password recovery',
        request
      )

      Result.new(
        authenticated: false,
        failure_limit_exceeded: limit_exceeded
      )
    end

    def recovery_code?(device, code)
      CryptoProviders::Bcrypt.matches?(device.recovery_code, nil, code)
    end
  end
end
