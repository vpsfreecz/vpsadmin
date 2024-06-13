require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::UserSession::Close < Operations::Base
    # @param user_session [::UserSession]
    def run(user_session)
      # Close session and revoke access token
      user_session.close!

      # Close relevant OAuth2 authorizations, there can be only one however
      user_session.oauth2_authorizations.each do |auth|
        auth.close

        sso = auth.single_sign_on

        sso.close if sso && (!sso.usable? || !sso.any_active_authorizations?)
      end

      # Close expired single sign ons
      ::SingleSignOn.where.not(token: nil).each do |sso|
        sso.close if !sso.usable? || !sso.any_active_authorizations?
      end

      nil
    end
  end
end
