module TransactionChains
  class User::SoftDelete < ::TransactionChain
    label 'Soft delete'

    def link_chain(user, target, state, log)
      mail(:user_soft_delete, {
        user: user,
        vars: {
          user: user,
          state: log,
        }
      })

      if target
        user.vpses.where(object_state: [
          ::Vps.object_states[:active],
          ::Vps.object_states[:suspended],
        ]).each do |vps|
          vps.set_object_state(
            :soft_delete,
            reason: 'User was soft deleted',
            chain: self
          )
        end
      end

      user.exports.each do |ex|
        use_chain(Export::Update, args: [ex, {enabled: false}])
      end

      user.user_sessions.where.not(token: nil).each do |user_session|
        user_session.close!
      end

      user.single_sign_ons.destroy_all
      user.oauth2_authorizations.destroy_all
    end
  end
end
