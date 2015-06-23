module TransactionChains
  class Pool::Create < ::TransactionChain
    label 'Create'

    def link_chain(pool)
      lock(pool)

      append(Transactions::Storage::CreatePool, args: pool)
    end
  end
end
