require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::UserSession::ResumeOAuth2 < Operations::Base
    # @param token [String]
    # @return [::UserSession, nil]
    def run(token)
      sess_token = ::SessionToken.joins(:token).where(
        'tokens.token = ? AND ((lifetime = 3 AND valid_to IS NULL) OR valid_to >= ?)',
        token, Time.now
      ).take

      return if sess_token.nil?

      user = sess_token.user

      if !%w(active suspended).include?(user.object_state)
        sess_token.destroy!
        return
      end

      ::SessionToken.increment_counter(:use_count, sess_token.id)

      if sess_token.lifetime == 'renewable_auto'
        sess_token.renew!
      end

      begin
        session = ::UserSession.find_for!(user, sess_token, :oauth2)
      rescue ActiveRecord::RecordNotFound
        ::UserSession.current = nil
        ::User.current = nil
        return
      end

      session.update!(last_request_at: Time.now)
      user.update!(last_request_at: Time.now)

      # Extend single sign on
      if sess_token.lifetime == 'renewable_auto'
        oauth = ::Oauth2Authorization.find_by(user_session: session)

        if oauth \
           && oauth.single_sign_on \
           && oauth.single_sign_on.token.valid_to < sess_token.valid_to
          oauth.single_sign_on.token.update!(valid_to: sess_token.valid_to)
        end
      end

      ::User.current = user
      ::UserSession.current = session
    end
  end
end
