module TransactionChains
  class User::NewToken < ::TransactionChain
    label 'New token'
    allow_empty

    # @param user_session [::UserSession]
    def link_chain(user_session)
      session_user = user_session.user

      concerns(:affect, [session_user.class.name, session_user.id])

      route_event!(
        'user.new_token',
        user: session_user,
        source: user_session,
        subject: 'New access token',
        summary: "New access token for #{session_user.login}",
        payload: {
          auth_type: user_session.auth_type,
          client_ip_addr: user_session.client_ip_addr,
          api_ip_addr: user_session.api_ip_addr,
          client_version: user_session.client_version,
          scope: user_session.scope_str,
          token_lifetime: user_session.token_lifetime,
          label: user_session.label
        },
        ip_addr: user_session.client_ip_addr || user_session.api_ip_addr
      )
    end
  end
end
