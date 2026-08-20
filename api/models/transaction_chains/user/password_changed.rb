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
               ip_address: request.env['HTTP_X_REAL_IP'].presence || request.ip,
               time: Time.current,
               support_mail: ::SysConfig.get(:core, :support_mail).to_s
             }
           })
    end
  end
end
