module TransactionChains
  class User::NewLogin < ::TransactionChain
    label 'New login'
    allow_empty

    # @param user_session [::UserSession]
    # @param authorization [::Oauth2Authorization]
    def link_chain(user_session, authorization)
      concerns(:affect, [user_session.user.class.name, user_session.user.id])

      mail(:user_new_login, {
             user:,
             vars: {
               user: user_session.user,
               user_session:,
               authorization:,
               user_device: authorization.user_device
             }
           })
    end
  end
end
