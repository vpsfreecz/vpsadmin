module TransactionChains
  class Vps::StopOverQuota < ::TransactionChain
    label 'StopQuota'

    def link_chain(dataset_expansion)
      lock(dataset_expansion.vps)
      concerns(
        :affect,
        [dataset_expansion.vps.class.name, dataset_expansion.vps.id],
        [dataset_expansion.dataset.class.name, dataset_expansion.dataset.id]
      )

      use_chain(Vps::Stop, args: [dataset_expansion.vps])

      mail(:vps_stopped_over_quota, {
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
