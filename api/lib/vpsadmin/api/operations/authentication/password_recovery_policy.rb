module VpsAdmin::API
  class Operations::Authentication::PasswordRecoveryPolicy < Operations::Base
    Result = Struct.new(:eligible, :mfa_methods, :denial_reason) do
      alias_method :eligible?, :eligible

      def effective_mfa?
        mfa_methods.any?
      end

      def administrator_account?
        denial_reason == :administrator
      end
    end

    def run(user, request, lock_mfa: false)
      unless user.role == :user
        return Result.new(
          eligible: false,
          mfa_methods: [],
          denial_reason: %i[support admin].include?(user.role) ? :administrator : :unavailable
        )
      end

      eligible = eligible?(user, request)
      Result.new(
        eligible:,
        mfa_methods: mfa_methods(user, lock: lock_mfa),
        denial_reason: eligible ? nil : :unavailable
      )
    end

    protected

    def eligible?(user, request)
      return false unless user.enable_oauth2_auth

      Operations::User::CheckLogin.run(
        user,
        request,
        allow_password_reset: true
      )
      true
    rescue Exceptions::OperationError
      false
    end

    def mfa_methods(user, lock: false)
      return [] unless user.enable_multi_factor_auth

      methods = []
      totp_devices = user.user_totp_devices.where(enabled: true, confirmed: true)
      passkeys = user.webauthn_credentials.where(enabled: true)
      totp_devices = totp_devices.lock if lock
      passkeys = passkeys.lock if lock
      methods << :totp if totp_devices.exists?
      methods << :webauthn if passkeys.exists?
      methods
    end
  end
end
