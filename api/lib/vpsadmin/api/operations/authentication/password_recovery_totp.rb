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

        policy = Operations::Authentication::PasswordRecoveryPolicy.run(user, request)
        unless policy.eligible? && policy.mfa_methods.include?(:totp)
          recovery.update!(invalidated_at: Time.current)
          return Result.new(authenticated: false)
        end

        recoveries = ::PasswordRecovery.lock_active_verified_with_totp(user)
        verification = Operations::Authentication::TotpFactor.run(user, code)
        if verification
          recovery.verify_mfa_with!(verification.device)

          if verification.recovery_code?
            ::PasswordRecovery.invalidate_locked_verified_with!(
              recoveries,
              verification.device,
              except: recovery
            )
            TransactionChains::User::TotpRecoveryCodeUsed.fire(
              user,
              verification.device,
              request
            )
          end

          return Result.new(
            authenticated: true,
            recovery_device: verification.recovery_code? ? verification.device : nil,
            failure_limit_exceeded: false
          )
        else
          record_failure(recovery, user, request)
        end
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
  end
end
