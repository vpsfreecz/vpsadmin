module TransactionChains
  class User::NewLogin < ::TransactionChain
    label 'New login'
    allow_empty

    # @param user_session [::UserSession]
    # @param authorization [::Oauth2Authorization]
    def link_chain(user_session, authorization)
      session_user = user_session.user

      concerns(:affect, [session_user.class.name, session_user.id])

      route_event!(
        'user.new_login',
        session: user_session,
        authorization:
      )
    end
  end
end
