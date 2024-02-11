module TransactionChains
  class Vps::Unblock < ::TransactionChain
    label 'Unblock'

    def link_chain(vps, target, _state, log)
      use_chain(Vps::Start, args: vps)

      return unless target && vps.user.mailer_enabled

      mail(:vps_resume, {
             user: vps.user,
             vars: {
               vps:,
               state: log
             }
           })
    end
  end
end
