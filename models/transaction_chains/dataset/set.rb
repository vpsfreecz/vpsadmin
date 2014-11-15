module TransactionChains
  class Dataset::Set < ::TransactionChain
    label 'Set dataset properties'

    def link_chain(dataset_in_pool, changes)
      lock(dataset_in_pool)

      append(Transactions::Storage::SetDataset, args: [dataset_in_pool, changes])
    end
  end
end
