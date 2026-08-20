module TransactionChains
  class User::PasswordChanged < ::TransactionChain
    label 'Password changed'

    def link_chain(user, request)
      concerns(:affect, [user.class.name, user.id])

      mail(:user_password_changed, {
             user:,
             vars: {
               user:,
               request:,
               time: Time.current,
               support_mail: ::SysConfig.get(:core, :support_mail).to_s
             }
           })
    end
  end
end
