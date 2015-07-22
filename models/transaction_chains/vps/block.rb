module TransactionChains
  class Vps::Block < ::TransactionChain
    label 'Block'

    def link_chain(vps, target, state, log)
      use_chain(Vps::Stop, args: vps)

      mail(:vps_suspend, {
          user: vps.user,
          vars: {
              vps: vps,
              state: log
          }
      }) if target
    end
  end
end
