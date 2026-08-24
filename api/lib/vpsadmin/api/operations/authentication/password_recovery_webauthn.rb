require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::PasswordRecoveryWebauthn < Operations::Base
    Result = Data.define(:authenticated, :error) do
      def authenticated?
        authenticated
      end
    end

    def run(recovery, challenge, public_key_credential, request)
      ::PasswordRecovery.transaction do
        user = recovery.user
        user.lock!
        recovery.lock!
        challenge = lock_challenge(recovery, challenge)

        policy = Operations::Authentication::PasswordRecoveryPolicy.run(user, request)
        unless recovery.session_usable? && !recovery.mfa_verified? &&
               policy.eligible? && policy.mfa_methods.include?(:webauthn) &&
               challenge&.token_valid?
          recovery.update!(invalidated_at: Time.current) unless policy.eligible?
          next Result.new(authenticated: false, error: nil)
        end

        begin
          raise ArgumentError, 'invalid WebAuthn input' unless public_key_credential

          credential = Operations::Authentication::WebauthnFactor.run(
            user,
            challenge,
            public_key_credential
          )
          challenge.destroy!
          recovery.verify_mfa_with!(credential)
          Result.new(authenticated: true, error: nil)
        rescue ArgumentError, ActiveRecord::RecordNotFound, WebAuthn::Error => e
          Result.new(authenticated: false, error: e)
        end
      end
    end

    protected

    def lock_challenge(recovery, challenge)
      ::WebauthnChallenge.joins(:token).includes(:token).where(
        id: challenge.id,
        password_recovery: recovery,
        challenge_type: 'authentication'
      ).lock.take
    end
  end
end
