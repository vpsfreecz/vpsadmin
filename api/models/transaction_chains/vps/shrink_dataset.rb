module TransactionChains
  class Vps::ShrinkDataset < ::TransactionChain
    label 'Shrink'

    def link_chain(dataset_in_pool, dataset_expansion)
      lock(dataset_in_pool)
      concerns(
        :affect,
        [dataset_expansion.vps.class.name, dataset_expansion.vps.id],
        [dataset_expansion.dataset.class.name, dataset_expansion.dataset.id],
      )

      use_chain(Dataset::Set, args: [
        dataset_in_pool,
        {refquota: dataset_expansion.original_refquota},
        {
          reset_expansion: false,
          admin_override: true,
          admin_lock_type: 'no_lock',
        },
      ])

      if dataset_expansion.vps.active? && dataset_expansion.enable_notifications
        mail(:vps_dataset_shrunk, {
          user: dataset_expansion.vps.user,
          vars: {
            base_url: ::SysConfig.get(:webui, :base_url),
            vps: dataset_expansion.vps,
            expansion: dataset_expansion,
            dataset: dataset_expansion.dataset,
          },
        })
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.edit(dataset_in_pool.dataset, dataset_expansion_id: nil)
        t.edit(dataset_expansion, state: ::DatasetExpansion.states[:resolved])
      end
    end
  end
end
