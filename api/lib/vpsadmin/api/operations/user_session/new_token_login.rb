require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::NewTokenLogin < Operations::Base
    include Operations::UserSession::Utils

    # @param user [User]
    # @param request [Sinatra::Request]
    # @param token_lifetime [String]
    # @param token_interval [Integer]
    # @param scope [Array<String>]
    # @param authentication_generation [Integer]
    # @return [::UserSession]
    def run(user, request, token_lifetime, token_interval, scope, authentication_generation:)
      ::UserSession.transaction do
        user.lock!
        if user.authentication_generation != authentication_generation
          raise Exceptions::OperationError, 'authentication expired'
        end

        Operations::User::Login.run(user, request)

        session = open_session(
          user:,
          request:,
          auth_type: :token,
          scope:,
          generate_token: true,
          token_lifetime:,
          token_interval:
        )

        ::UserSession.current = session

        if session.user.enable_new_login_notification
          TransactionChains::User::NewToken.fire2(args: [session])
        end

        session
      end
    end
  end
end
