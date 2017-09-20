module TransactionChains
  class User::SoftDelete < ::TransactionChain
    label 'Soft delete'

    def link_chain(user, target, state, log)
      mail(:user_soft_delete, {
          user: user,
          vars: {
              user: user,
              state: log
          }
      })

      user.vpses.where(object_state: [
          ::Vps.object_states[:active],
          ::Vps.object_states[:suspended],
      ]).each do |vps|
        vps.set_object_state(:soft_delete, reason: 'User was soft deleted',
                             chain: self)
      end
    end
  end
end
