require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::CloseToken < Operations::Base
    include Operations::UserSession::Utils

    # @param user [User]
    # @param token [::SessionToken, String]
    def run(user, token)
      if token.is_a?(::SessionToken)
        sess_token = token
      else
        begin
          sess_token = ::SessionToken.joins(:token).where(
            user: user,
            tokens: {token: token},
          ).take!
        rescue ActiveRecord::RecordNotFound
          raise Exceptions::OperationError, 'session not found'
        end
      end

      begin
        session = ::UserSession.find_for!(user, sess_token)
      rescue ActiveRecord::RecordNotFound
        raise Exceptions::OperationError, 'session not found'
      end

      session.close!
    end
  end
end
