module TransactionChains
  class Vps::Unblock < ::TransactionChain
    label 'Unblock'

    def link_chain(vps, target, state, log)
      use_chain(Vps::Start, args: vps)

      mail(:vps_resume, {
          user: vps.user,
          vars: {
              vps: vps,
              state: log
          }
      }) if target && vps.user.mailer_enabled
    end
  end
end
