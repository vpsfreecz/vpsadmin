require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::NewBasicLogin < Operations::Base
    include Operations::UserSession::Utils

    # @param user [User]
    # @param request [Sinatra::Request]
    # @return [::UserSession]
    def run(user, request)
      Operations::User::Login.run(user, request)

      session = open_session(user, request, :basic, nil)
      session.close!
      ::UserSession.current = session
    end
  end
end
