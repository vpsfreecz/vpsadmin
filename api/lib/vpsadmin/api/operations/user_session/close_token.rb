require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::CloseToken < Operations::Base
    include Operations::UserSession::Utils

    # @param user [User]
    # @param token [String]
    def run(user, token)
      begin
        user_session = ::UserSession.joins(:token).where(
          user: user,
          auth_type: :token,
          tokens: {token: token},
        ).take!
      rescue ActiveRecord::RecordNotFound
        raise Exceptions::OperationError, 'session not found'
      end

      user_session.close!
    end
  end
end
