require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::NewTokenLogin < Operations::Base
    include Operations::UserSession::Utils

    # @param user [User]
    # @param request [Sinatra::Request]
    # @param lifetime [String]
    # @param interval [Integer]
    # @return [::UserSession]
    def run(user, request, lifetime, interval)
      Operations::User::Login.run(user, request)

      token = ::SessionToken.custom!(
        user: user,
        lifetime: lifetime,
        interval: interval,
        label: request.user_agent,
      )

      session = open_session(user, request, :token, token)
      ::UserSession.current = session
    end
  end
end
