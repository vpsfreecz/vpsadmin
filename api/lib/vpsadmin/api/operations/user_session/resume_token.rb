require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::UserSession::ResumeToken < Operations::Base
    # @param token [String]
    # @return [::UserSession, nil]
    def run(token)
      user_session = ::UserSession
        .joins(:token)
        .where(auth_type: 'token', closed_at: nil)
        .where(
          'tokens.token = ? AND ((token_lifetime = 3 AND tokens.valid_to IS NULL) OR tokens.valid_to >= ?)',
          token, Time.now
        ).take

      if user_session.nil? \
         || !%w(active suspended).include?(user_session.user.object_state)
        ::UserSession.current = nil
        ::User.current = nil
        return
      end

      ::UserSession.increment_counter(:request_count, user_session.id)

      if user_session.token_lifetime == 'renewable_auto'
        user_session.renew_token!
      end

      user_session.update!(last_request_at: Time.now)
      user_session.user.update!(last_request_at: Time.now)

      ::User.current = user_session.user
      ::UserSession.current = user_session
    end
  end
end
