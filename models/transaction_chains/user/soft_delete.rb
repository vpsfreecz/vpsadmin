module TransactionChains
  class User::SoftDelete < ::TransactionChain
    label 'Soft delete user'

    def link_chain(user, target, state, log)
      mail(:user_soft_delete, {
          user: user,
          vars: {
              user: user,
              state: log
          }
      })

      user.vps.where(object_state: %i(active suspended)).each do |vps|
        vps.set_object_state(:soft_delete, reason: 'User was soft deleted',
                             chain: self)
      end
    end
  end
end
