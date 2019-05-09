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

      if totp.verify(code)
        auth_token.destroy!
        auth_token
      else
        false
      end
    end
  end
end
