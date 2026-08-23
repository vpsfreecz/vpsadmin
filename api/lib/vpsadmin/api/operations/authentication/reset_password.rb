require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::ResetPassword < Operations::Base
    Result = Struct.new(:user, :password_change_log)

    include PasswordChanges::ClientInfo

    # @param auth_token [AuthToken]
    # @param new_password [String]
    # @param request [Sinatra::Request]
    # @return [Result]
    def run(auth_token, new_password, request:)
      user = auth_token.user

      user.with_lock do
        current_token = ::AuthToken.find_by(id: auth_token.id)
        unless current_token&.token_valid? && current_token.authentication_current?
          raise Exceptions::AuthenticationError, 'invalid token'
        end

        user.set_password(
          new_password,
          source: :forced_reset,
          user_session: nil,
          **password_change_client_info(request)
        )
        user.save!
        ::TransactionChains::User::PasswordChanged.fire(user, request)
        Result.new(user, user.recorded_password_change)
      end
    end
  end
end
