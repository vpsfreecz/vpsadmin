module TransactionChains
  class PasswordRecoveryMail < ::TransactionChain
    label 'Password recovery mail'

    def link_chain(recovery_request, accounts, language)
      concerns(
        :affect,
        *recovery_request.password_recoveries.map { |recovery| ['User', recovery.user_id] }
      )

      mail(:password_recovery, {
             language:,
             to: [recovery_request.recipient_email],
             cc: [],
             bcc: [],
             exclusive_recipients: true,
             vars: {
               accounts:,
               support_mail: ::SysConfig.get(:core, :support_mail).to_s,
               expires_at: Time.current + ::PasswordRecovery::EMAIL_LIFETIME
             }
           })
    end
  end
end
