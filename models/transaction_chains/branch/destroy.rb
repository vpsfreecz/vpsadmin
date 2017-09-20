module TransactionChains
  class Branch::Destroy < ::TransactionChain
    label 'Destroy dataset branch'

    def link_chain(branch)
      lock(branch)
      branch.update!(confirmed: ::Branch.confirmed(:confirm_destroy))

      append(Transactions::Storage::DestroyBranch, args: branch) do
        destroy(branch)
      end
    end
  end
end
