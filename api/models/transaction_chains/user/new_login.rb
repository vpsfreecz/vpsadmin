module TransactionChains
  class User::NewLogin < ::TransactionChain
    label 'New login'
    allow_empty

    # @param user_session [::UserSession]
    # @param authorization [::Oauth2Authorization]
    def link_chain(user_session, authorization)
      session_user = user_session.user
      user_device = authorization.user_device

      concerns(:affect, [session_user.class.name, session_user.id])

      route_event!(
        'user.new_login',
        user: session_user,
        source: user_session,
        subject: 'New sign-in',
        summary: "New sign-in to #{session_user.login}",
        parameters: {
          auth_type: user_session.auth_type,
          client_ip_addr: user_session.client_ip_addr,
          api_ip_addr: user_session.api_ip_addr,
          client_version: user_session.client_version,
          user_agent: user_session.user_agent_string,
          user_device_id: user_device&.id,
          authorization_id: authorization.id,
          oauth2_client_id: authorization.oauth2_client_id
        },
        ip_addr: user_session.client_ip_addr || user_session.api_ip_addr,
        email_vars: {
          user: session_user,
          user_session:,
          authorization:,
          user_device:
        }
      )
    end
  end
end
