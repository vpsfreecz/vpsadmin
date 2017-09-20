module TransactionChains
  class User::Resume < ::TransactionChain
    label 'Resume'

    def link_chain(user, target, state, log)
      mail(:user_resume, {
          user: user,
          vars: {
              user: user,
              state: log
          }
      }) if target

      user.vpses.where(object_state: ::Vps.object_states[:active]).each do |vps|
        use_chain(Vps::Start, args: vps)
      end
    end
  end
end
