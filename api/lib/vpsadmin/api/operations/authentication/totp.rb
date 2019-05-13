require 'rotp'
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
      totp = ROTP::TOTP.new(user.totp_secret)
      last_use_at = totp.verify(code, after: user.totp_last_use_at)

      if last_use_at || is_recovery_code?(user, code)
        user.update!(totp_last_use_at: last_use_at) if last_use_at
        auth_token.destroy!
        Result.new(user, auth_token)
      else
        Result.new(user, nil)
      end
    end

    protected
    def is_recovery_code?(user, code)
      CryptoProviders::Bcrypt.matches?(user.totp_recovery_code, nil, code)
    end
  end
end
