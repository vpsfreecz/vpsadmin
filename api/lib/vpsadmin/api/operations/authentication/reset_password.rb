require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::ResetPassword < Operations::Base
    # @param token [String]
    # @param new_password [String]
    # @return [User]
    def run(token, new_password)
      auth_token = ::AuthToken.joins(:token).includes(:token, :user).find_by(
        tokens: { token: token },
        purpose: 'reset_password'
      )

      raise Exceptions::AuthenticationError, 'invalid token' if auth_token.nil? || !auth_token.token_valid?

      user = auth_token.user
      user.set_password(new_password)
      user.save!
      auth_token.destroy!
      user
    end
  end
end
