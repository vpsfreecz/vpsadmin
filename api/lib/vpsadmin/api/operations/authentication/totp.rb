require 'rotp'
require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::Totp < Operations::Base
    # @param token [String]
    # @param code [String]
    # @return [::AuthToken, false]
    def run(token, code)
      auth_token = ::AuthToken.joins(:token).includes(:token, :user).find_by(
        tokens: {token: token},
      )

      if auth_token.nil? || !auth_token.token_valid?
        raise Exceptions::AuthenticationError, 'invalid token'
      end

      totp = ROTP::TOTP.new(auth_token.user.totp_secret)

      if totp.verify(code) || is_recovery_code?(auth_token.user, code)
        auth_token.destroy!
        auth_token
      else
        false
      end
    end

    protected
    def is_recovery_code?(user, code)
      CryptoProviders::Bcrypt.matches?(user.totp_recovery_code, nil, code)
    end
  end
end
