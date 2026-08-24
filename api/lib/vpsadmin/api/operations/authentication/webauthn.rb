require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::Webauthn < Operations::Base
    def run(auth_token, challenge, public_key_credential)
      user = auth_token.user
      user.with_lock do
        auth_token = lock_auth_token(user, auth_token)
        challenge = lock_challenge(user, challenge)
        unless challenge.token_valid?
          raise Exceptions::AuthenticationError, 'challenge token expired'
        end
        unless auth_token.token_valid? && auth_token.authentication_current?
          raise Exceptions::AuthenticationError, 'auth token expired'
        end

        credential = Operations::Authentication::WebauthnFactor.run(
          user,
          challenge,
          public_key_credential
        )
        challenge.destroy!
        auth_token.update!(fulfilled: true)
        credential
      end
    end

    protected

    def lock_auth_token(user, auth_token)
      ::AuthToken.joins(:token).includes(:token, :user).where(
        id: auth_token.id,
        user:,
        purpose: 'mfa'
      ).lock.take!
    end

    def lock_challenge(user, challenge)
      ::WebauthnChallenge.joins(:token).includes(:token).where(
        id: challenge.id,
        user:,
        challenge_type: 'authentication',
        password_recovery_id: nil
      ).lock.take!
    end
  end
end
