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
    # @return [::UserSession]
    def run(user, request, token_lifetime, token_interval, scope)
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
    end
  end
end
