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
          reset_expansion: false,
          admin_override: true,
          admin_lock_type: 'no_lock',
        },
      ])

      begin
        vps = exp.dataset.root.primary_dataset_in_pool!.vpses.where(object_state: 'active').take!
      rescue ActiveRecord::RecordNotFound
        # pass
      else
        mail(:vps_dataset_shrunk, {
          user: vps.user,
          vars: {
            base_url: ::SysConfig.get(:webui, :base_url),
            vps: vps,
            expansion: dataset_expansion,
            dataset: dataset_expansion.dataset,
          },
        })
      end

      append_t(Transaction::Utils::NoOp, args: find_node_id) do |t|
        t.edit(dataset_in_pool.dataset, dataset_expansion_id: nil)
        t.edit(dataset_expansion, state: ::DatasetExpansion.states[:resolved])
      end
    end
  end
end
