module TransactionChains
  class User::Revive < ::TransactionChain
    label 'Revive'

    def link_chain(user, _target, _state, log)
      mail(:user_revive, {
             user:,
             vars: {
               user:,
               state: log
             }
           })

      user.exports.where(original_enabled: true).each do |ex|
        use_chain(Export::Update, args: [ex, { enabled: true }])
      end

      user.vpses.where(object_state: ::Vps.object_states[:soft_delete]).each do |vps|
        vps.set_object_state(:active, reason: 'User was revived', chain: self)
      end
    end
  end
end
