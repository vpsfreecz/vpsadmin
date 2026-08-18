require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::NewBasicLogin < Operations::Base
    include Operations::UserSession::Utils

    # @param user [User]
    # @param request [Sinatra::Request]
    # @param authentication_generation [Integer]
    # @return [::UserSession]
    def run(user, request, authentication_generation:)
      ::UserSession.transaction do
        user.lock!
        if user.authentication_generation != authentication_generation
          raise Exceptions::OperationError, 'authentication expired'
        end

        Operations::User::Login.run(user, request)

        session = open_session(
          user:,
          request:,
          auth_type: :basic,
          generate_token: false,
          scope: ['all']
        )
        session.close!
        ::UserSession.current = session
      end
    end
  end
end
