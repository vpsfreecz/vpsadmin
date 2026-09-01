module TransactionChains
  class Mail::VpsDatasetExpanded < ::TransactionChain
    label 'Dataset expanded'

    def link_chain(dataset_expansion, new_refquota:, added_space: dataset_expansion.added_space)
      dataset = dataset_expansion.dataset
      dataset_in_pool = dataset.primary_dataset_in_pool!

      concerns(:affect, [dataset_expansion.vps.class.name, dataset_expansion.vps.id])

      mail(:vps_dataset_expanded, {
             user: dataset_expansion.vps.user,
             vars: {
               base_url: ::SysConfig.get(:webui, :base_url),
               vps: dataset_expansion.vps,
               expansion: dataset_expansion,
               dataset:,
               original_refquota: dataset_expansion.original_refquota,
               new_refquota:,
               added_space:,
               referenced: dataset_in_pool.referenced
             }
           })
    end
  end
end
