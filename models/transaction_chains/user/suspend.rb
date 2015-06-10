module TransactionChains
  class User::Suspend < ::TransactionChain
    label 'Suspend user'

    def link_chain(user, target, state, log)
      mail(:user_suspend, {
          user: user,
          vars: {
              user: user,
              state: log
          }
      }) if target

      user.vpses.where(object_state: %i(active suspended)).each do |vps|
        use_chain(Vps::Stop, args: vps)
      end
    end
  end
end
