module TransactionChains
  class User::TotpRecoveryCodeUsed < ::TransactionChain
    label 'TOTP recovery'

    def link_chain(user, totp_device, request)
      concerns(:affect, [user.class.name, user.id])

      mail(:user_totp_recovery_code_used, {
        user: user,
        vars: {
          user: user,
          totp_device: totp_device,
          request: request,
          time: Time.now,
        }
      })
    end
  end
end
