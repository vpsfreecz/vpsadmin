module TransactionChains
  class User::Revive < ::TransactionChain
    label 'Revive'

    def link_chain(user, target, state, log)
      mail(:user_revive, {
        user: user,
        vars: {
          user: user,
          state: log,
        }
      })

      user.vpses.where(object_state: ::Vps.object_states[:soft_delete]).each do |vps|
        vps.set_object_state(:active, reason: 'User was revived', chain: self)
      end
    end
  end
end
