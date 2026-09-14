module TransactionChains
  class User::LoginEmailVerification < ::TransactionChain
    label 'Login email verification'

    def link_chain(auth_token, code, _request)
      user = auth_token.user
      concerns(:affect, [user.class.name, user.id])
      message = mail(:user_login_email_verification, {
                       user:, to: [auth_token.opts.fetch('email')], cc: [], bcc: [],
                       exclusive_recipients: true,
                       vars: { user:, code:, expires_at: auth_token.valid_to,
                               service_name: auth_token.opts.fetch('service_name'),
                               requested_at: auth_token.created_at,
                               device: auth_token.user_agent.to_user_friendly_s,
                               ip_address: auth_token.client_ip_addr,
                               ip_ptr: auth_token.client_ip_ptr,
                               user_agent: auth_token.user_agent.agent,
                               support_mail: ::SysConfig.get(:core, :support_mail).to_s }
                     })
      raise VpsAdmin::API::EmailLogin::Error, 'email_login_unavailable' unless message
    end
  end
end
