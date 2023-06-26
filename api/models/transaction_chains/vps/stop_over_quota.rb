module TransactionChains
  class Vps::StopOverQuota < ::TransactionChain
    label 'StopQuota'

    def link_chain(vps, dataset_expansion)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      use_chain(Vps::Stop, args: [vps])

      mail(:vps_stopped_over_quota, {
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
