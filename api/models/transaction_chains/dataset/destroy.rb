module TransactionChains
  class Dataset::Destroy < ::TransactionChain
    label 'Destroy'

    def link_chain(ds, target, state, log)
      lock(ds)

      ds.dataset_in_pools
          .where.not(confirmed: ::DatasetInPool.confirmed(:confirm_destroy))
          .each do |dip|
        use_chain(DatasetInPool::Destroy, args: [dip, {recursive: true}])
      end
    end
  end
end
