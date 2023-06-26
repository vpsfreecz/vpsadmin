module TransactionChains
  class Mail::VpsDatasetExpanded < ::TransactionChain
    label 'Dataset expanded'

    def link_chain(vps, dataset_expansion)
      concerns(:affect, [vps.class.name, vps.id])

      mail(:vps_dataset_expanded, {
        user: vps.user,
        vars: {
          base_url: ::SysConfig.get(:webui, :base_url),
          vps: vps,
          expansion: dataset_expansion,
          dataset: dataset_expansion.dataset,
        },
      })
    end
  end
end
