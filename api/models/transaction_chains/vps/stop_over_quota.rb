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

      vps = dataset_expansion.vps
      dataset = dataset_expansion.dataset
      route_event!(
        'vps.stopped_over_quota',
        user: vps.user,
        vps:,
        source: dataset_expansion,
        subject: "VPS ##{vps.id} stopped over quota",
        summary: "Dataset #{dataset.full_name} is over quota",
        parameters: {
          vps_id: vps.id,
          vps_hostname: vps.hostname,
          dataset_id: dataset.id,
          dataset_full_name: dataset.full_name,
          dataset_refquota: dataset.refquota,
          dataset_referenced: dataset.referenced,
          expansion_id: dataset_expansion.id,
          original_refquota: dataset_expansion.original_refquota,
          added_space: dataset_expansion.added_space,
          expansion_count: dataset_expansion.expansion_count,
          over_refquota_seconds: dataset_expansion.over_refquota_seconds,
          max_over_refquota_seconds: dataset_expansion.max_over_refquota_seconds,
          enable_shrink: dataset_expansion.enable_shrink
        }
      )
    end
  end
end
