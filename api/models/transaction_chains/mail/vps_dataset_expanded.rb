module TransactionChains
  class Mail::VpsDatasetExpanded < ::TransactionChain
    label 'Dataset expanded'

    def link_chain(dataset_expansion)
      concerns(:affect, [dataset_expansion.vps.class.name, dataset_expansion.vps.id])

      mail(:vps_dataset_expanded, {
             user: dataset_expansion.vps.user,
             vars: {
               base_url: ::SysConfig.get(:webui, :base_url),
               vps: dataset_expansion.vps,
               expansion: dataset_expansion,
               dataset: dataset_expansion.dataset
             }
           })
    end
  end
end
