module TransactionChains
  class User::LoginEmailVerification < ::TransactionChain
    label 'Login email verification'

    def link_chain(auth_token, code, request)
      user = auth_token.user
      concerns(:affect, [user.class.name, user.id])
      message = mail(:user_login_email_verification, {
                       user:, to: [auth_token.opts.fetch('email')], cc: [], bcc: [],
                       exclusive_recipients: true,
                       vars: { user:, code:, expires_at: auth_token.valid_to,
                               ip_address: request.env['HTTP_X_REAL_IP'].presence || request.ip,
                               user_agent: request.user_agent.to_s,
                               support_mail: ::SysConfig.get(:core, :support_mail).to_s }
                     })
      raise VpsAdmin::API::EmailLogin::Error, 'email_login_unavailable' unless message
    end
  end
end
