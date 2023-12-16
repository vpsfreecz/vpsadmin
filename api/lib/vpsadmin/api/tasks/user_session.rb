module VpsAdmin::API::Tasks
  class UserSession < Base
    # Close expired user sessions
    #
    # Accepts the following environment variables:
    # [EXECUTE]: The sessions are closed only when set to 'yes'
    def close_expired
      ::SessionToken.joins(:token).includes(:user_sessions).where(
        'tokens.valid_to IS NOT NULL AND tokens.valid_to < ?',
        Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      ).each do |t|
        puts "Token ##{t.id} valid_to=#{t.valid_to} token=#{t.token}"

        ::SessionToken.transaction do
          # There is never more than one user session
          t.user_sessions.each do |s|
            puts "  Close session ##{s.id}"
            next if ENV['EXECUTE'] != 'yes'

            oauth2_open = false

            # There can be only one authorization per session
            s.oauth2_authorizations.each do |auth|
              oauth2_open = true if auth.refreshable?
            end

            session_update = {session_token: nil}

            # Close the session only if oauth2 access token cannot be refreshed
            session_update[:closed_at] = t.valid_to unless oauth2_open

            s.update!(session_update)
          end

          t.destroy! if ENV['EXECUTE'] == 'yes'
        end
      end

      # Close oauth2 authorizations where even the refresh token has expired
      ::Oauth2Authorization
        .joins(:user_session, :refresh_token)
        .where(user_sessions: {closed_at: nil})
        .where.not(refresh_token: nil)
        .where('tokens.valid_to < ?', Time.now)
        .each do |auth|
        puts "OAuth2 authorization ##{auth.id} refresh token expired"
        auth.close if ENV['EXECUTE'] == 'yes'
      end

      # Close expired single sign ons
      ::SingleSignOn.where.not(token: nil).each do |sso|
        if !sso.usable? || !sso.any_active_authorizations?
          puts "Closing SSO session #{sso.id}"
          sso.close if ENV['EXECUTE'] == 'yes'
        end
      end
    end
  end
end
