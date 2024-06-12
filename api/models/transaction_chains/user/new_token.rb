module TransactionChains
  class User::NewToken < ::TransactionChain
    label 'New token'
    allow_empty

    # @param user_session [::UserSession]
    def link_chain(user_session)
      concerns(:affect, [user_session.user.class.name, user_session.user.id])

      mail(:user_new_token, {
             user:,
             vars: {
               user: user_session.user,
               user_session:
             }
           })
    end
  end
end
