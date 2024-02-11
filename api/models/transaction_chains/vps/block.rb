module TransactionChains
  class Vps::Block < ::TransactionChain
    label 'Block'

    def link_chain(vps, target, _state, log)
      use_chain(Vps::Stop, args: vps)

      return unless target && vps.user.mailer_enabled

      mail(:vps_suspend, {
             user: vps.user,
             vars: {
               vps:,
               state: log
             }
           })
    end
  end
end
