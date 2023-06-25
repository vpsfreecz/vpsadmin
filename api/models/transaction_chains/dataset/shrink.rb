module TransactionChains
  class Dataset::Shrink < ::TransactionChain
    label 'Shrink'

    def link_chain(dataset_in_pool, dataset_expansion)
      lock(dataset_in_pool)
      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

      use_chain(Dataset::Set, args: [
        dataset_in_pool,
        {refquota: dataset_expansion.original_refquota},
        {
          admin_override: true,
          admin_lock_type: 'no_lock',
        },
      ])

      append_t(Transaction::Utils::NoOp, args: find_node_id) do |t|
        t.edit(dataset_in_pool.dataset, dataset_expansion_id: nil)
        t.edit(dataset_expansion, state: ::DatasetExpansion.states[:resolved])
      end
    end
  end
end
