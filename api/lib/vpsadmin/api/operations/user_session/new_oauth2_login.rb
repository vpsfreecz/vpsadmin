require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::NewOAuth2Login < Operations::Base
    include Operations::UserSession::Utils

    # @param authorization [Oauth2Authorization]
    # @param request [Sinatra::Request]
    # @param token_lifetime [String]
    # @param token_interval [Integer]
    # @param scope [Array<String>]
    # @return [::UserSession]
    def run(authorization, request, token_lifetime, token_interval, scope)
      Operations::User::Login.run(authorization.user, request)

      session = open_session(
        user: authorization.user,
        request:,
        auth_type: :oauth2,
        scope:,
        generate_token: true,
        token_lifetime:,
        token_interval:
      )

      ::UserSession.current = session

      return session if authorization.user_device.known

      TransactionChains::User::NewLogin.fire2(args: [session, authorization.user_device])
      authorization.user_device.update!(known: true)

      session
    end
  end
end
