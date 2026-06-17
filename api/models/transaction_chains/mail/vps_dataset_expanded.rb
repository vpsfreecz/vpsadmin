module TransactionChains
  class Mail::VpsDatasetExpanded < ::TransactionChain
    label 'Dataset expanded'

    def link_chain(dataset_expansion)
      vps = dataset_expansion.vps
      dataset = dataset_expansion.dataset

      concerns(:affect, [vps.class.name, vps.id])

      route_event!(
        'vps.dataset_expanded',
        user: vps.user,
        vps:,
        source: dataset_expansion,
        subject: "Dataset for VPS ##{vps.id} expanded",
        summary: "Dataset #{dataset.full_name} was expanded by #{dataset_expansion.added_space} MiB",
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
          expansion_count: dataset_expansion.expansion_count
        },
        email_vars: {
          base_url: ::SysConfig.get(:webui, :base_url),
          vps:,
          expansion: dataset_expansion,
          dataset:
        }
      )
    end
  end
end
