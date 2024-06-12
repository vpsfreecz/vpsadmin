module TransactionChains
  class User::NewLogin < ::TransactionChain
    label 'New login'
    allow_empty

    def link_chain(user_session, user_device)
      concerns(:affect, [user_session.user.class.name, user_session.user.id])

      mail(:user_new_login, {
             user:,
             vars: {
               user: user_session.user,
               user_session:,
               user_device:
             }
           })
    end
  end
end
