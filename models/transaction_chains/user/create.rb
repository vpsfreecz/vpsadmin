module TransactionChains
  # This chain does nothing by default. It is used to call hooks
  # for user creation.
  class User::Create < ::TransactionChain
    label 'Create user'

    def link_chain(user)
      user.save!
      user.call_class_hooks_for(:create, self, args: [user])
    end
  end
end
