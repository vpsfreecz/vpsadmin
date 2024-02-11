module TransactionChains
  class User::Suspend < ::TransactionChain
    label 'Suspend'

    def link_chain(user, target, _state, log)
      if target
        mail(:user_suspend, {
               user:,
               vars: {
                 user:,
                 state: log
               }
             })
      end

      user.vpses.where(object_state: [
                         ::Vps.object_states[:active],
                         ::Vps.object_states[:suspended]
                       ]).each do |vps|
        use_chain(Vps::Stop, args: vps)
      end
    end
  end
end
